# frozen_string_literal: true

module A2A
  module Models
    class Message < Base
      attribute :message_id
      attribute :role,               required: true
      attribute :parts,              type: [Part], default: -> { [] }, required: true
      attribute :context_id
      attribute :task_id
      attribute :reference_task_ids, default: -> { [] }
      attribute :metadata
      attribute :extensions,         default: -> { [] }

      def self.user(*content)
        new(message_id: SecureRandom.uuid, role: Types::Role::USER, parts: build_parts(content))
      end


      def self.agent(*content)
        new(message_id: SecureRandom.uuid, role: Types::Role::AGENT, parts: build_parts(content))
      end


      def self.build_parts(content)
        content.map { |c| c.is_a?(Part) ? c : Part.text(c.to_s) }
      end
      private_class_method :build_parts

      def initialize(**kwargs)
        kwargs[:message_id] ||= SecureRandom.uuid
        super
      end


      def user?  = role == Types::Role::USER
      def agent? = role == Types::Role::AGENT


      def text_content
        parts.select(&:text?).map(&:text).join("\n")
      end


      def valid?
        !role.nil? && !parts.nil? && !parts.empty?
      end
    end
  end
end
