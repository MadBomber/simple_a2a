# frozen_string_literal: true

module A2A
  module Models
    class AgentProvider < Base
      attribute :name, required: true
      attribute :url
      attribute :description
    end
  end
end
