# frozen_string_literal: true

require "test_helper"

class TestStreamResponse < Minitest::Test
  def test_from_hash_with_task
    task = A2A::Models::Task.new(
      id: "t-1",
      status: A2A::Models::TaskStatus.new(state: "submitted", timestamp: "2026-01-01T00:00:00Z")
    )
    h = { "task" => task.to_h }
    sr = A2A::Models::StreamResponse.from_hash(h)
    assert sr.task?
    assert_equal "t-1", sr.task.id
    refute sr.message?
    refute sr.status_update?
    refute sr.artifact_update?
  end

  def test_from_hash_with_message
    msg = A2A::Models::Message.user("hi")
    h = { "message" => msg.to_h }
    sr = A2A::Models::StreamResponse.from_hash(h)
    assert sr.message?
    assert_equal "hi", sr.message.text_content
    refute sr.task?
  end

  def test_from_hash_with_status_update
    h = { "statusUpdate" => { "state" => "working" } }
    sr = A2A::Models::StreamResponse.from_hash(h)
    assert sr.status_update?
    assert_equal({ "state" => "working" }, sr.status_update)
  end

  def test_from_hash_with_artifact_update
    h = { "artifactUpdate" => { "name" => "result" } }
    sr = A2A::Models::StreamResponse.from_hash(h)
    assert sr.artifact_update?
  end

  def test_from_hash_nil_returns_nil
    assert_nil A2A::Models::StreamResponse.from_hash(nil)
  end

  def test_from_hash_unknown_returns_empty
    sr = A2A::Models::StreamResponse.from_hash({})
    refute sr.task?
    refute sr.message?
  end
end

class TestSendMessageConfiguration < Minitest::Test
  def test_defaults
    cfg = A2A::Models::SendMessageConfiguration.new
    assert_equal [], cfg.accepted_output_modes
    assert_equal false, cfg.return_immediately
    assert_nil cfg.history_length
    assert_nil cfg.task_push_notification_config
  end

  def test_custom_values
    cfg = A2A::Models::SendMessageConfiguration.new(
      accepted_output_modes: ["text"],
      history_length: 10,
      return_immediately: true
    )
    assert_equal ["text"], cfg.accepted_output_modes
    assert_equal 10, cfg.history_length
    assert cfg.return_immediately
  end

  def test_to_h_snake_to_camel
    cfg = A2A::Models::SendMessageConfiguration.new(
      accepted_output_modes: ["text"],
      history_length: 5
    )
    h = cfg.to_h
    assert h.key?("acceptedOutputModes")
    assert h.key?("historyLength")
    assert h.key?("returnImmediately")
  end
end

class TestPushNotification < Minitest::Test
  def test_authentication_info_valid
    auth = A2A::Models::AuthenticationInfo.new(scheme: "bearer", value: "token123")
    assert auth.valid?
    assert_equal "bearer", auth.scheme
    assert_equal "token123", auth.value
  end

  def test_authentication_info_requires_scheme_and_value
    auth = A2A::Models::AuthenticationInfo.new(scheme: "bearer", value: nil)
    refute auth.valid?
  end

  def test_push_notification_config_valid
    cfg = A2A::Models::PushNotificationConfig.new(webhook_url: "https://example.com/hook")
    assert cfg.valid?
  end

  def test_push_notification_config_invalid_without_url
    cfg = A2A::Models::PushNotificationConfig.new(webhook_url: nil)
    refute cfg.valid?
  end

  def test_push_notification_config_invalid_with_empty_url
    cfg = A2A::Models::PushNotificationConfig.new(webhook_url: "")
    refute cfg.valid?
  end

  def test_push_notification_config_with_auth
    auth = A2A::Models::AuthenticationInfo.new(scheme: "bearer", value: "tok")
    cfg = A2A::Models::PushNotificationConfig.new(
      webhook_url: "https://example.com/hook",
      authentication_info: auth
    )
    assert_equal "bearer", cfg.authentication_info.scheme
  end

  def test_from_hash_coerces_authentication_info
    h = {
      "webhookUrl" => "https://example.com/hook",
      "authenticationInfo" => { "scheme" => "bearer", "value" => "tok" }
    }
    cfg = A2A::Models::PushNotificationConfig.from_hash(h)
    assert cfg.valid?
    assert_instance_of A2A::Models::AuthenticationInfo, cfg.authentication_info
    assert_equal "bearer", cfg.authentication_info.scheme
  end
end
