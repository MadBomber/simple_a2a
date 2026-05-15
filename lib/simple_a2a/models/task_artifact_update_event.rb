# frozen_string_literal: true

module A2A
  module Models
    class TaskArtifactUpdateEvent < Base
      attribute :task_id,    required: true
      attribute :context_id, required: true
      attribute :artifact,   type: Artifact, required: true
      attribute :append,     default: false
      attribute :last_chunk, default: false
      attribute :metadata

      def append?     = !!append
      def last_chunk? = !!last_chunk


      def to_h
        super.merge("type" => "TaskArtifactUpdateEvent")
      end
    end
  end
end
