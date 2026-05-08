# frozen_string_literal: true

module A2A
  module Models
    class Artifact < Base
      attribute :artifact_id
      attribute :name
      attribute :description
      attribute :parts,      type: [Part], default: -> { [] }
      attribute :metadata
      attribute :extensions, default: -> { [] }

      def initialize(**kwargs)
        kwargs[:artifact_id] ||= SecureRandom.uuid
        super
      end

      def valid?
        !parts.nil? && !parts.empty?
      end
    end
  end
end
