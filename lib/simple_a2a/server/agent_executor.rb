# frozen_string_literal: true

module A2A
  module Server
    class AgentExecutor
      def call(context)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      def cancel(context)
        context.task.cancel!
        context.emit_status(final: true)
      end
    end
  end
end
