# frozen_string_literal: true

module A2A
  module Models
    class AgentSkill < Base
      attribute :name,         required: true
      attribute :description
      attribute :input_schema
      attribute :output_schema
    end
  end
end
