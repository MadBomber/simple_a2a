# frozen_string_literal: true

module A2A
  module Models
    class AgentCapabilities < Base
      attribute :streaming,           default: false
      attribute :push_notifications,  default: false
      attribute :extended_agent_card, default: false
    end
  end
end
