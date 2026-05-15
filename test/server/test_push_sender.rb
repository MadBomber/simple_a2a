# frozen_string_literal: true

require "test_helper"

class TestPushSender < Minitest::Test
  def setup
    @sender = A2A::Server::PushSender.new
    @config = A2A::Models::PushNotificationConfig.new(webhook_url: "https://example.com/hook")
    @event  = A2A::Models::TaskStatusUpdateEvent.new(
      task_id: "t-1",
      context_id: "c-1",
      status: A2A::Models::TaskStatus.new(state: "completed", timestamp: "2026-01-01T00:00:00Z"),
      final: true
    )
  end


  def test_deliver_returns_false_for_nil_config
    refute @sender.deliver(nil, @event)
  end


  def test_deliver_returns_false_for_invalid_config
    bad = A2A::Models::PushNotificationConfig.new(webhook_url: "")
    refute @sender.deliver(bad, @event)
  end


  def test_deliver_returns_false_for_non_config
    refute @sender.deliver("not a config", @event)
  end


  def test_deliver_returns_false_on_connection_error
    config = A2A::Models::PushNotificationConfig.new(webhook_url: "http://localhost:1")
    result = @sender.deliver(config, @event)
    refute result
  end


  def test_build_headers_no_auth
    sender = A2A::Server::PushSender.new
    headers = sender.send(:build_headers, @config, "{}")
    assert_equal "application/json", headers["Content-Type"]
    refute headers.key?("Authorization")
  end


  def test_build_headers_bearer_no_key
    auth = A2A::Models::AuthenticationInfo.new(scheme: "bearer", value: "unused")
    config = A2A::Models::PushNotificationConfig.new(
      webhook_url: "https://example.com/hook",
      authentication_info: auth
    )
    headers = @sender.send(:build_headers, config, "{}")
    assert headers.key?("Authorization")
    assert_match(/^Bearer /, headers["Authorization"])
  end


  def test_build_headers_custom_header_name
    auth = A2A::Models::AuthenticationInfo.new(
      scheme: "token", value: "my-token", header_name: "X-Webhook-Token"
    )
    config = A2A::Models::PushNotificationConfig.new(
      webhook_url: "https://example.com/hook",
      authentication_info: auth
    )
    headers = @sender.send(:build_headers, config, "{}")
    assert headers.key?("X-Webhook-Token")
    assert_equal "Token my-token", headers["X-Webhook-Token"]
  end


  def test_build_payload_is_json
    payload = @sender.send(:build_payload, @event)
    parsed = JSON.parse(payload)
    assert_equal "t-1", parsed["taskId"]
    assert_equal true, parsed["final"]
  end
end
