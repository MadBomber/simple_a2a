# frozen_string_literal: true

module A2A
  module Server
    class BroadcastRegistry
      def initialize
        @broadcasts = {}
        @mutex      = Mutex.new
      end

      def register(task_id, broadcast)
        @mutex.synchronize { @broadcasts[task_id] = broadcast }
      end

      def unregister(task_id)
        @mutex.synchronize { @broadcasts.delete(task_id) }
      end

      def find(task_id)
        @mutex.synchronize { @broadcasts[task_id] }
      end
    end
  end
end
