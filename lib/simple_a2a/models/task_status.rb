# frozen_string_literal: true

module A2A
  module Models
    class TaskStatus < Base
      attribute :state,     required: true
      attribute :message,   type: Message
      attribute :timestamp

      def initialize(**kwargs)
        kwargs[:timestamp] ||= Time.now.iso8601
        super
      end

      def terminal?    = Types::TaskState.terminal?(state)
      def interrupted? = Types::TaskState.interrupted?(state)
      def active?      = Types::TaskState.active?(state)
    end
  end
end
