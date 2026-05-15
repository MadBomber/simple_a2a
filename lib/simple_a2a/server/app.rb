# frozen_string_literal: true

require "roda"
require "protocol/http/body/writable"

module A2A
  module Server
    class App < Roda
      SUPPORTED_VERSIONS = %w[1.0 0.3].freeze
      SSE_METHODS        = %w[tasks/sendSubscribe tasks/resubscribe].freeze
      DISPATCH_TABLE     = {
        "tasks/send" => :handle_send,
        "tasks/get" => :handle_get,
        "tasks/list" => :handle_list,
        "tasks/cancel" => :handle_cancel,
        "tasks/pushNotification/set" => :handle_push_set,
        "tasks/pushNotification/get" => :handle_push_get,
        "tasks/pushNotification/delete" => :handle_push_delete,
        "tasks/pushNotification/list" => :handle_push_list
      }.freeze

      plugin :json
      plugin :json_parser
      plugin :halt
      plugin :all_verbs

      include SseHandlers
      include PushHandlers

      def self.configure(agent_card:, storage:, executor:, broadcast_registry:, push_sender: nil,
                         push_config_store: nil)
        @agent_card         = agent_card
        @storage            = storage
        @executor           = executor
        @broadcast_registry = broadcast_registry
        @push_sender        = push_sender
        @push_config_store  = push_config_store || PushConfigStore.new
      end

      class << self
        attr_reader :agent_card, :storage, :executor, :broadcast_registry, :push_sender, :push_config_store
      end

      route do |r|
        a2a_version = request.env["HTTP_A2A_VERSION"]
        if a2a_version && !SUPPORTED_VERSIONS.include?(a2a_version)
          err = JsonRpc::Response.error(
            id: nil,
            code: JsonRpc::ErrorCode::VERSION_NOT_SUPPORTED,
            message: "Unsupported A2A version: #{a2a_version}"
          )
          r.halt([200, { "Content-Type" => "application/json" }, [err]])
        end

        r.get "agentCard" do
          self.class.agent_card.to_h
        end

        r.on ".well-known" do
          r.get "agent-card.json" do
            self.class.agent_card.to_h
          end
        end

        r.post do
          body    = request.body.read
          rpc_req = parse_request(r, body)

          handle_sse_request(r, rpc_req) if SSE_METHODS.include?(rpc_req.method)

          result = dispatch(rpc_req)
          response["Content-Type"] = "application/json"
          result
        end
      end

      private

      def parse_request(rda, body)
        JsonRpc::Request.parse(body)
      rescue JsonRpc::ParseError => e
        err = JsonRpc::Response.error(id: nil, code: JsonRpc::ErrorCode::PARSE_ERROR, message: e.message)
        rda.halt([200, { "Content-Type" => "application/json" }, [err]])
      rescue JsonRpc::InvalidRequestError => e
        err = JsonRpc::Response.error(id: nil, code: JsonRpc::ErrorCode::INVALID_REQUEST, message: e.message)
        rda.halt([200, { "Content-Type" => "application/json" }, [err]])
      end


      def handle_sse_request(rda, rpc_req)
        sse_body = if rpc_req.method == "tasks/sendSubscribe"
                     handle_send_subscribe(rpc_req)
                   else
                     handle_resubscribe(rpc_req)
                   end
        rda.halt([200, {
                   "Content-Type" => "text/event-stream",
                   "Cache-Control" => "no-cache",
                   "X-Accel-Buffering" => "no"
                 }, sse_body])
      rescue A2A::Error, JsonRpc::InvalidParamsError => e
        err = JsonRpc::Response.from_error(id: rpc_req.id, error: e)
        rda.halt([200, { "Content-Type" => "application/json" }, [err]])
      end


      def dispatch(rpc_req)
        handler = DISPATCH_TABLE[rpc_req.method]
        return send(handler, rpc_req) if handler

        JsonRpc::Response.error(
          id: rpc_req.id,
          code: JsonRpc::ErrorCode::METHOD_NOT_FOUND,
          message: "Method not found: #{rpc_req.method}"
        )
      rescue StandardError => e
        JsonRpc::Response.from_error(id: rpc_req.id, error: e)
      end


      def resolve_task_id!(params)
        params ||= {}
        id = params["id"] || params["taskId"]
        raise JsonRpc::InvalidParamsError, "id is required" unless id

        id
      end


      def build_context(task:, message:, broadcast:)
        Server::Context.new(
          task: task, message: message, storage: self.class.storage, event_router: broadcast
        )
      end


      def handle_send(rpc_req)
        params   = rpc_req.params || {}
        msg_hash = params["message"]
        raise JsonRpc::InvalidParamsError, "message is required" unless msg_hash.is_a?(Hash)

        message = Models::Message.from_hash(msg_hash)
        task    = Models::Task.new(
          status: Models::TaskStatus.new(state: Models::Types::TaskState::SUBMITTED)
        )
        self.class.storage.save(task)

        ctx = build_context(task: task, message: message, broadcast: TaskBroadcast.new)
        self.class.executor.call(ctx)
        self.class.storage.save(task)

        JsonRpc::Response.success(id: rpc_req.id, result: task.to_h)
      end


      def handle_get(rpc_req)
        task_id = resolve_task_id!(rpc_req.params)
        task    = self.class.storage.find!(task_id)
        JsonRpc::Response.success(id: rpc_req.id, result: task.to_h)
      end


      def handle_list(rpc_req)
        tasks = self.class.storage.list
        JsonRpc::Response.success(id: rpc_req.id, result: tasks.map(&:to_h))
      end


      def handle_cancel(rpc_req)
        task_id   = resolve_task_id!(rpc_req.params)
        task      = self.class.storage.find!(task_id)
        raise TaskNotCancelableError, "Task #{task_id} is already terminal" if task.terminal?

        broadcast = self.class.broadcast_registry.find(task_id) || TaskBroadcast.new
        ctx       = build_context(task: task, message: nil, broadcast: broadcast)
        self.class.executor.cancel(ctx)
        self.class.storage.save(task)
        JsonRpc::Response.success(id: rpc_req.id, result: task.to_h)
      end
    end
  end
end
