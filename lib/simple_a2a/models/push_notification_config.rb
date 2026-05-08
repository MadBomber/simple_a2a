# frozen_string_literal: true

module A2A
  module Models
    class PushNotificationConfig < Base
      attribute :id
      attribute :task_id
      attribute :webhook_url,         required: true
      attribute :authentication_info, type: AuthenticationInfo
      attribute :event_types,         default: -> { [] }

      def valid?
        !webhook_url.nil? && !webhook_url.empty?
      end
    end
  end
end
