# frozen_string_literal: true

module A2A
  module Models
    class TaskStatusUpdateEvent < Base
      attribute :task_id,    required: true
      attribute :context_id, required: true
      attribute :status,     type: TaskStatus, required: true
      attribute :final,      default: false
      attribute :metadata

      def final? = !!final

      def to_h
        super.merge("type" => "TaskStatusUpdateEvent")
      end
    end
  end
end
