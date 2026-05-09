# frozen_string_literal: true

module A2A
  module Server
    class PushConfigStore
      def initialize
        @configs = {}
        @mutex   = Mutex.new
      end

      def set(task_id, config)
        @mutex.synchronize { @configs[task_id] = config }
        config
      end

      def get(task_id)
        @mutex.synchronize { @configs[task_id] }
      end

      def delete(task_id)
        @mutex.synchronize { @configs.delete(task_id) }
      end

      def list
        @mutex.synchronize { @configs.dup }
      end
    end
  end
end
