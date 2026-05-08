# frozen_string_literal: true

module A2A
  module Models
    class AgentCard < Base
      attribute :name,             required: true
      attribute :description
      attribute :version,          required: true
      attribute :provider,         type: AgentProvider
      attribute :capabilities,     type: AgentCapabilities, required: true
      attribute :skills,           type: [AgentSkill],      default: -> { [] }, required: true
      attribute :interfaces,       type: [AgentInterface],  default: -> { [] }, required: true
      attribute :security_schemes, default: -> { [] }
      attribute :security,         default: -> { [] }
      attribute :extensions,       default: -> { [] }

      def valid?
        !name.nil? && !version.nil? && !capabilities.nil? &&
          !skills.nil? && !interfaces.nil?
      end
    end
  end
end
