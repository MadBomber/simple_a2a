# frozen_string_literal: true

require "test_helper"

class TestErrors < Minitest::Test
  def test_base_error_is_standard_error
    assert_operator SimpleA2a::Error, :<, StandardError
  end

  def test_all_errors_inherit_from_base
    [
      SimpleA2a::ConfigurationError,
      SimpleA2a::TaskNotFoundError,
      SimpleA2a::TaskNotCancelableError,
      SimpleA2a::PushNotificationNotSupportedError,
      SimpleA2a::UnsupportedOperationError,
      SimpleA2a::ContentTypeNotSupportedError,
      SimpleA2a::InvalidAgentResponseError,
      SimpleA2a::ExtensionSupportRequiredError,
      SimpleA2a::VersionNotSupportedError,
      SimpleA2a::ExtendedAgentCardNotConfiguredError
    ].each do |klass|
      assert_operator klass, :<, SimpleA2a::Error, "#{klass} should inherit from SimpleA2a::Error"
    end
  end
end
