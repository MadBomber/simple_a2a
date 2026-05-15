# frozen_string_literal: true

module A2A
  module Storage
    class Memory < Base
      def initialize
        super
        @store = {}
        @mutex = Mutex.new
      end


      def save(task)
        @mutex.synchronize { @store[task.id] = task }
        task
      end


      def find(id)
        @mutex.synchronize { @store[id] }
      end


      def find!(id)
        find(id) or raise TaskNotFoundError, "Task #{id} not found"
      end


      def delete(id)
        @mutex.synchronize { @store.delete(id) }
      end


      def list
        @mutex.synchronize { @store.values.dup }
      end


      def size
        @mutex.synchronize { @store.size }
      end


      def clear
        @mutex.synchronize { @store.clear }
      end
    end
  end
end
