# frozen_string_literal: true

module A2A
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TaskNotFoundError < Error; end
  class TaskNotCancelableError < Error; end
  class PushNotificationNotSupportedError < Error; end
  class UnsupportedOperationError < Error; end
  class ContentTypeNotSupportedError < Error; end
  class InvalidAgentResponseError < Error; end
  class ExtensionSupportRequiredError < Error; end
  class VersionNotSupportedError < Error; end
  class ExtendedAgentCardNotConfiguredError < Error; end
end
