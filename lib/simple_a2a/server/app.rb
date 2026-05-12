# frozen_string_literal: true

require "roda"
require "protocol/http/body/writable"

module A2A
  module Server
    class App < Roda
      SUPPORTED_VERSIONS = %w[1.0 0.3].freeze
      SSE_METHODS        = %w[tasks/sendSubscribe tasks/resubscribe].freeze

      plugin :json
      plugin :json_parser
      plugin :halt
      plugin :all_verbs

      def self.configure(agent_card:, storage:, executor:, broadcast_registry:, push_sender: nil, push_config_store: nil)
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

          if SSE_METHODS.include?(rpc_req.method)
            begin
              sse_body = rpc_req.method == "tasks/sendSubscribe" ?
                         handle_send_subscribe(rpc_req) :
                         handle_resubscribe(rpc_req)
              r.halt([200, {
                "Content-Type"      => "text/event-stream",
                "Cache-Control"     => "no-cache",
                "X-Accel-Buffering" => "no"
              }, sse_body])
            rescue A2A::Error, JsonRpc::InvalidParamsError => e
              err = JsonRpc::Response.from_error(id: rpc_req.id, error: e)
              r.halt([200, { "Content-Type" => "application/json" }, [err]])
            end
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
        task_id  = params["id"]

        task, ctx = if task_id
          existing = self.class.storage.find!(task_id)
          unless existing.status.interrupted?
            raise UnsupportedOperationError,
                  "Task #{task_id} cannot be resumed: state is #{existing.status.state}"
          end
          resume_ctx = Server::ResumeContext.new(
            task:           existing,
            message:        message,
            resume_message: message,
            storage:        self.class.storage,
            event_router:   TaskBroadcast.new
          )
          [existing, resume_ctx]
        else
          new_task = Models::Task.new(
            status: Models::TaskStatus.new(state: Models::Types::TaskState::SUBMITTED)
          )
          self.class.storage.save(new_task)
          new_ctx = Server::Context.new(
            task:         new_task,
            message:      message,
            storage:      self.class.storage,
            event_router: TaskBroadcast.new
          )
          [new_task, new_ctx]
        end

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

        # Use the live broadcast if streaming; otherwise events are discarded (no subscribers).
        broadcast = self.class.broadcast_registry.find(task_id) || TaskBroadcast.new

        ctx = Server::Context.new(
          task:         task,
          message:      nil,
          storage:      self.class.storage,
          event_router: broadcast
        )
        self.class.executor.cancel(ctx)
        self.class.storage.save(task)

        JsonRpc::Response.success(id: rpc_req.id, result: task.to_h)
      end

      def handle_send_subscribe(rpc_req)
        params   = rpc_req.params || {}
        msg_hash = params["message"]
        raise JsonRpc::InvalidParamsError, "message is required" unless msg_hash.is_a?(Hash)
        message = Models::Message.from_hash(msg_hash)

        task = Models::Task.new(
          status: Models::TaskStatus.new(state: Models::Types::TaskState::SUBMITTED)
        )
        self.class.storage.save(task)

        broadcast = TaskBroadcast.new
        queue     = broadcast.subscribe
        self.class.broadcast_registry.register(task.id, broadcast)

        storage  = self.class.storage
        executor = self.class.executor
        registry = self.class.broadcast_registry
        output   = Protocol::HTTP::Body::Writable.new

        Async::Task.current.async do
          ctx = Server::Context.new(
            task:         task,
            message:      message,
            storage:      storage,
            event_router: broadcast
          )
          executor.call(ctx)
          storage.save(task)
        rescue => e
          broadcast.error(e.message)
        ensure
          broadcast.close
          registry.unregister(task.id)
        end

        Async::Task.current.async do
          loop do
            event = queue.async_pop
            break if event.equal?(TaskBroadcast::DONE)
            if event.is_a?(TaskBroadcast::BroadcastError)
              output.write(sse_error_frame(event.message)) rescue nil
              break
            end
            output.write(sse_frame(event))
          end
        rescue => e
          output.write(sse_error_frame(e.message)) rescue nil
        ensure
          broadcast.unsubscribe(queue)
          output.close_write rescue nil
        end

        output
      end

      def handle_resubscribe(rpc_req)
        params  = rpc_req.params || {}
        task_id = params["id"] || params["taskId"]
        raise JsonRpc::InvalidParamsError, "id is required" unless task_id

        task = self.class.storage.find!(task_id)
        raise UnsupportedOperationError, "Task #{task_id} is in a terminal state" if task.terminal?

        broadcast = self.class.broadcast_registry.find(task_id)
        raise UnsupportedOperationError, "Task #{task_id} is no longer streaming" unless broadcast

        queue  = broadcast.subscribe
        output = Protocol::HTTP::Body::Writable.new

        # Spec requires the current Task snapshot as the first SSE event.
        output.write(sse_frame(task))

        Async::Task.current.async do
          loop do
            event = queue.async_pop
            break if event.equal?(TaskBroadcast::DONE)
            if event.is_a?(TaskBroadcast::BroadcastError)
              output.write(sse_error_frame(event.message)) rescue nil
              break
            end
            output.write(sse_frame(event))
          end
        rescue => e
          output.write(sse_error_frame(e.message)) rescue nil
        ensure
          broadcast.unsubscribe(queue)
          output.close_write rescue nil
        end

        output
      end

      def handle_push_set(rpc_req)
        raise PushNotificationNotSupportedError unless self.class.agent_card&.capabilities&.push_notifications

        params  = rpc_req.params || {}
        task_id = params["id"] or raise JsonRpc::InvalidParamsError, "id is required"
        cfg_h   = params["pushNotificationConfig"]
        raise JsonRpc::InvalidParamsError, "pushNotificationConfig is required" unless cfg_h.is_a?(Hash)

        self.class.storage.find!(task_id)

        config = Models::PushNotificationConfig.from_hash(cfg_h.merge("taskId" => task_id))
        raise JsonRpc::InvalidParamsError, "pushNotificationConfig.webhookUrl is required" unless config.valid?

        self.class.push_config_store.set(task_id, config)
        result = { "id" => task_id, "pushNotificationConfig" => config.to_h }
        JsonRpc::Response.success(id: rpc_req.id, result: result)
      end

      def handle_push_get(rpc_req)
        raise PushNotificationNotSupportedError unless self.class.agent_card&.capabilities&.push_notifications

        params  = rpc_req.params || {}
        task_id = params["id"] or raise JsonRpc::InvalidParamsError, "id is required"

        config = self.class.push_config_store.get(task_id)
        result = config ? { "id" => task_id, "pushNotificationConfig" => config.to_h } : nil
        JsonRpc::Response.success(id: rpc_req.id, result: result)
      end

      def handle_push_delete(rpc_req)
        raise PushNotificationNotSupportedError unless self.class.agent_card&.capabilities&.push_notifications

        params  = rpc_req.params || {}
        task_id = params["id"] or raise JsonRpc::InvalidParamsError, "id is required"

        self.class.push_config_store.delete(task_id)
        JsonRpc::Response.success(id: rpc_req.id, result: nil)
      end

      def handle_push_list(rpc_req)
        raise PushNotificationNotSupportedError unless self.class.agent_card&.capabilities&.push_notifications

        configs = self.class.push_config_store.list
        result  = configs.map { |tid, cfg| { "id" => tid, "pushNotificationConfig" => cfg.to_h } }
        JsonRpc::Response.success(id: rpc_req.id, result: result)
      end

      def sse_frame(result)
        "data: #{JSON.generate({ 'jsonrpc' => '2.0', 'result' => result.to_h })}\n\n"
      end

      def sse_error_frame(message)
        "data: #{JSON.generate({ 'jsonrpc' => '2.0', 'error' => { 'code' => -32_000, 'message' => message } })}\n\n"
      end
    end
  end
end
