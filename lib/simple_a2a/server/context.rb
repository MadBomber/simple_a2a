# frozen_string_literal: true

module A2A
  module Server
    class Context
      attr_reader :task, :message, :storage, :event_router, :config

      def initialize(task:, message:, storage:, event_router:, config: nil)
        @task         = task
        @message      = message
        @storage      = storage
        @event_router = event_router
        @config       = config || {}
      end


      def save_task
        storage.save(task)
      end


      def emit_status(final: false)
        event = Models::TaskStatusUpdateEvent.new(
          task_id: task.id,
          context_id: task.context_id,
          status: task.status,
          final: final
        )
        storage.save(task)
        event_router.publish(task.id, event)
      end


      def emit_artifact(artifact, append: false, last_chunk: false)
        event = Models::TaskArtifactUpdateEvent.new(
          task_id: task.id,
          context_id: task.context_id,
          artifact: artifact,
          append: append,
          last_chunk: last_chunk
        )
        event_router.publish(task.id, event)
      end
    end
  end
end
