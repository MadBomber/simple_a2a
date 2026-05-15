# frozen_string_literal: true

module A2A
  module Models
    class Task < Base
      attribute :id
      attribute :context_id
      attribute :status,    type: TaskStatus, required: true
      attribute :artifacts, type: [Artifact], default: -> { [] }
      attribute :history,   type: [Message],  default: -> { [] }
      attribute :metadata

      def initialize(**kwargs)
        kwargs[:id]         ||= SecureRandom.uuid
        kwargs[:context_id] ||= SecureRandom.uuid
        super
      end


      def state        = status&.state
      def terminal?    = status&.terminal? || false
      def interrupted? = status&.interrupted? || false


      def start!
        transition!(Types::TaskState::WORKING)
      end


      def complete!(artifacts: [])
        self.artifacts = artifacts unless artifacts.empty?
        transition!(Types::TaskState::COMPLETED)
      end


      def fail!(message: nil)
        transition!(Types::TaskState::FAILED, message: message)
      end


      def cancel!
        transition!(Types::TaskState::CANCELED)
      end


      def reject!(message: nil)
        transition!(Types::TaskState::REJECTED, message: message)
      end


      def require_input!(message: nil)
        transition!(Types::TaskState::INPUT_REQUIRED, message: message)
      end


      def require_auth!(message: nil)
        transition!(Types::TaskState::AUTH_REQUIRED, message: message)
      end


      def transition!(new_state, message: nil)
        self.status = TaskStatus.new(state: new_state, message: message)
      end
    end
  end
end
