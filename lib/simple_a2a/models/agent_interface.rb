# frozen_string_literal: true

module A2A
  module Models
    class AgentInterface < Base
      attribute :type,    required: true
      attribute :url,     required: true
      attribute :version, required: true
    end
  end
end
