# frozen_string_literal: true

module A2A
  module Models
    class AuthenticationInfo < Base
      attribute :scheme,      required: true
      attribute :value,       required: true
      attribute :header_name
    end
  end
end
