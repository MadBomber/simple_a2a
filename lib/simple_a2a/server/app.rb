# frozen_string_literal: true

require "roda"

module A2A
  module Server
    class App < Roda
      SUPPORTED_VERSIONS = %w[1.0 0.3].freeze

      plugin :json
      plugin :json_parser
      plugin :halt
      plugin :all_verbs

      def self.configure(agent_card:, storage:, executor:, event_router:, push_sender: nil)
        @agent_card   = agent_card
        @storage      = storage
        @executor     = executor
        @event_router = event_router
        @push_sender  = push_sender
      end

      class << self
        attr_reader :agent_card, :storage, :executor, :event_router, :push_sender
      end

      route do |r|
        # A2A version negotiation
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

        r.post do
          body = request.body.read
          rpc_req = begin
            JsonRpc::Request.parse(body)
          rescue JsonRpc::ParseError => e
            err = JsonRpc::Response.error(id: nil, code: JsonRpc::ErrorCode::PARSE_ERROR, message: e.message)
            r.halt([200, { "Content-Type" => "application/json" }, [err]])
          rescue JsonRpc::InvalidRequestError => e
            err = JsonRpc::Response.error(id: nil, code: JsonRpc::ErrorCode::INVALID_REQUEST, message: e.message)
            r.halt([200, { "Content-Type" => "application/json" }, [err]])
          end

          result = dispatch(rpc_req)
          response["Content-Type"] = "application/json"
          result
        end
      end

      private

      def dispatch(rpc_req)
        case rpc_req.method
        when "tasks/send"                    then handle_send(rpc_req)
        when "tasks/sendSubscribe"           then handle_send_subscribe(rpc_req)
        when "tasks/get"                     then handle_get(rpc_req)
        when "tasks/list"                    then handle_list(rpc_req)
        when "tasks/cancel"                  then handle_cancel(rpc_req)
        when "tasks/pushNotification/set"    then handle_push_set(rpc_req)
        when "tasks/pushNotification/get"    then handle_push_get(rpc_req)
        when "tasks/pushNotification/delete" then handle_push_delete(rpc_req)
        when "tasks/pushNotification/list"   then handle_push_list(rpc_req)
        else
          JsonRpc::Response.error(
            id:      rpc_req.id,
            code:    JsonRpc::ErrorCode::METHOD_NOT_FOUND,
            message: "Method not found: #{rpc_req.method}"
          )
        end
      rescue A2A::Error => e
        JsonRpc::Response.from_error(id: rpc_req.id, error: e)
      rescue StandardError => e
        JsonRpc::Response.from_error(id: rpc_req.id, error: e)
      end

      def handle_send(rpc_req)
        params   = rpc_req.params || {}
        msg_hash = params["message"]
        raise JsonRpc::InvalidParamsError, "message is required" unless msg_hash.is_a?(Hash)
        message  = Models::Message.from_hash(msg_hash)

        task = Models::Task.new(
          status: Models::TaskStatus.new(state: Models::Types::TaskState::SUBMITTED)
        )
        self.class.storage.save(task)

        ctx = Server::Context.new(
          task:         task,
          message:      message,
          storage:      self.class.storage,
          event_router: self.class.event_router
        )
        self.class.executor.call(ctx)
        self.class.storage.save(task)

        JsonRpc::Response.success(id: rpc_req.id, result: task.to_h)
      end

      def handle_get(rpc_req)
        params  = rpc_req.params || {}
        task_id = params["id"] || params["taskId"]
        raise JsonRpc::InvalidParamsError, "id is required" unless task_id

        task = self.class.storage.find!(task_id)
        JsonRpc::Response.success(id: rpc_req.id, result: task.to_h)
      end

      def handle_list(rpc_req)
        tasks = self.class.storage.list
        JsonRpc::Response.success(id: rpc_req.id, result: tasks.map(&:to_h))
      end

      def handle_cancel(rpc_req)
        params  = rpc_req.params || {}
        task_id = params["id"] || params["taskId"]
        raise JsonRpc::InvalidParamsError, "id is required" unless task_id

        task = self.class.storage.find!(task_id)
        raise TaskNotCancelableError, "Task #{task_id} is already terminal" if task.terminal?

        ctx = Server::Context.new(
          task:         task,
          message:      nil,
          storage:      self.class.storage,
          event_router: self.class.event_router
        )
        self.class.executor.cancel(ctx)
        self.class.storage.save(task)

        JsonRpc::Response.success(id: rpc_req.id, result: task.to_h)
      end

      def handle_send_subscribe(rpc_req)
        raise UnsupportedOperationError, "Streaming requires SSE client"
      end

      def handle_push_set(rpc_req)
        raise PushNotificationNotSupportedError unless self.class.agent_card&.capabilities&.push_notifications
        JsonRpc::Response.success(id: rpc_req.id, result: true)
      end

      def handle_push_get(rpc_req)
        raise PushNotificationNotSupportedError unless self.class.agent_card&.capabilities&.push_notifications
        JsonRpc::Response.success(id: rpc_req.id, result: nil)
      end

      def handle_push_delete(rpc_req)
        raise PushNotificationNotSupportedError unless self.class.agent_card&.capabilities&.push_notifications
        JsonRpc::Response.success(id: rpc_req.id, result: true)
      end

      def handle_push_list(rpc_req)
        raise PushNotificationNotSupportedError unless self.class.agent_card&.capabilities&.push_notifications
        JsonRpc::Response.success(id: rpc_req.id, result: [])
      end
    end
  end
end
