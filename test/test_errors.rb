# frozen_string_literal: true

require "test_helper"

class TestErrors < Minitest::Test
  def test_base_error_is_standard_error
    assert_operator A2A::Error, :<, StandardError
  end

  def test_all_errors_inherit_from_base
    [
      A2A::ConfigurationError,
      A2A::TaskNotFoundError,
      A2A::TaskNotCancelableError,
      A2A::PushNotificationNotSupportedError,
      A2A::UnsupportedOperationError,
      A2A::ContentTypeNotSupportedError,
      A2A::InvalidAgentResponseError,
      A2A::ExtensionSupportRequiredError,
      A2A::VersionNotSupportedError,
      A2A::ExtendedAgentCardNotConfiguredError
    ].each do |klass|
      assert_operator klass, :<, A2A::Error, "#{klass} should inherit from A2A::Error"
    end
  end
end
