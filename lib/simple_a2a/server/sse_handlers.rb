# frozen_string_literal: true

module A2A
  module Server
    module SseHandlers
      private

      def handle_send_subscribe(rpc_req)
        params   = rpc_req.params || {}
        msg_hash = params["message"]
        raise JsonRpc::InvalidParamsError, "message is required" unless msg_hash.is_a?(Hash)

        message   = Models::Message.from_hash(msg_hash)
        task      = Models::Task.new(
          status: Models::TaskStatus.new(state: Models::Types::TaskState::SUBMITTED)
        )
        self.class.storage.save(task)

        broadcast = TaskBroadcast.new
        queue     = broadcast.subscribe
        self.class.broadcast_registry.register(task.id, broadcast)
        output    = Protocol::HTTP::Body::Writable.new

        run_executor_async(task: task, message: message, broadcast: broadcast)
        run_sse_writer_async(output: output, broadcast: broadcast, queue: queue)
        output
      end


      def handle_resubscribe(rpc_req)
        task_id = resolve_task_id!(rpc_req.params)
        task    = self.class.storage.find!(task_id)
        raise UnsupportedOperationError, "Task #{task_id} is in a terminal state" if task.terminal?

        broadcast = self.class.broadcast_registry.find(task_id)
        raise UnsupportedOperationError, "Task #{task_id} is no longer streaming" unless broadcast

        queue  = broadcast.subscribe
        output = Protocol::HTTP::Body::Writable.new
        output.write(sse_frame(task))

        run_sse_writer_async(output: output, broadcast: broadcast, queue: queue)
        output
      end


      def run_executor_async(task:, message:, broadcast:)
        storage  = self.class.storage
        executor = self.class.executor
        registry = self.class.broadcast_registry

        Async::Task.current.async do
          ctx = Server::Context.new(
            task: task, message: message, storage: storage, event_router: broadcast
          )
          executor.call(ctx)
          storage.save(task)
        rescue StandardError => e
          broadcast.error(e.message)
        ensure
          broadcast.close
          registry.unregister(task.id)
        end
      end


      def run_sse_writer_async(output:, broadcast:, queue:)
        Async::Task.current.async do
          loop do
            event = queue.async_pop
            break if event.equal?(TaskBroadcast::DONE)

            if event.is_a?(TaskBroadcast::BroadcastError)
              safely_write(output, sse_error_frame(event.message))
              break
            end
            output.write(sse_frame(event))
          end
        rescue StandardError => e
          safely_write(output, sse_error_frame(e.message))
        ensure
          broadcast.unsubscribe(queue)
          safely_close_write(output)
        end
      end


      def sse_frame(result)
        "data: #{JSON.generate({ "jsonrpc" => "2.0", "result" => result.to_h })}\n\n"
      end


      def sse_error_frame(message)
        "data: #{JSON.generate({ "jsonrpc" => "2.0",
                                 "error" => { "code" => -32_000, "message" => message } })}\n\n"
      end


      def safely_write(output, data)
        output.write(data)
      rescue StandardError
        nil
      end


      def safely_close_write(output)
        output.close_write
      rescue StandardError
        nil
      end
    end
  end
end
