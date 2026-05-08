# frozen_string_literal: true

module A2A
  module Models
    class SendMessageConfiguration < Base
      attribute :accepted_output_modes,          default: -> { [] }
      attribute :task_push_notification_config
      attribute :history_length
      attribute :return_immediately,             default: false
    end
  end
end
