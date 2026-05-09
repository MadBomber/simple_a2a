# frozen_string_literal: true

require "ractor_queue"

module A2A
  module Server
    class TaskBroadcast
      DONE = :done.freeze

      BroadcastError = Struct.new(:message)

      def initialize
        @queues = []
        @mutex  = Mutex.new
      end

      def subscribe(capacity: 64)
        RactorQueue.new(capacity: capacity).tap do |q|
          @mutex.synchronize { @queues << q }
        end
      end

      def unsubscribe(queue)
        @mutex.synchronize { @queues.delete(queue) }
      end

      # Duck-type compatible with the old EventRouter interface.
      # task_id is accepted but ignored — the broadcast is already task-scoped.
      def publish(_task_id, event)
        snapshot = @mutex.synchronize { @queues.dup }
        snapshot.each { |q| q.async_push(event) }
      end

      def error(message)
        ev = BroadcastError.new(message)
        snapshot = @mutex.synchronize { @queues.dup }
        snapshot.each { |q| q.async_push(ev) }
      end

      def close
        snapshot = @mutex.synchronize { @queues.dup }
        snapshot.each { |q| q.async_push(DONE) }
      end
    end
  end
end
