# frozen_string_literal: true

module A2A
  module Models
    class SecurityScheme < Base
      attribute :type,             required: true
      attribute :description
      attribute :scheme
      attribute :bearer_format
      attribute :flows
      attribute :open_id_connect_url
      attribute :in
      attribute :name
    end
  end
end
