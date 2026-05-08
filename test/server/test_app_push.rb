# frozen_string_literal: true

require "test_helper"
require "rack/test"

class TestServerAppPush < Minitest::Test
  include Rack::Test::Methods

  M = A2A::Models

  def build_app(push_notifications:)
    storage  = A2A::Storage::Memory.new
    router   = A2A::Server::EventRouter.new
    card     = M::AgentCard.new(
      name:         "PushTestAgent",
      version:      "1.0",
      capabilities: M::AgentCapabilities.new(push_notifications: push_notifications),
      skills:       [M::AgentSkill.new(name: "test")],
      interfaces:   [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
    klass = Class.new(A2A::Server::App)
    klass.configure(
      agent_card:   card,
      storage:      storage,
      executor:     A2A::Server::AgentExecutor.new,
      event_router: router
    )
    klass.freeze.app
  end

  def app = build_app(push_notifications: false)

  def json_post(method, params = {}, rack_app = app)
    @_rack_app = rack_app
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params })
    post "/", body, "CONTENT_TYPE" => "application/json"
    JSON.parse(last_response.body)
  end

  # Rack::Test::Methods uses #app; override to allow passing a different app
  alias original_app app
  def app = @_rack_app || original_app

  # --- push notifications disabled (default) ---

  def test_push_set_returns_not_supported_when_capability_false
    resp = json_post("tasks/pushNotification/set", {})
    assert_equal A2A::JsonRpc::ErrorCode::PUSH_NOT_SUPPORTED, resp.dig("error", "code")
  end

  def test_push_get_returns_not_supported_when_capability_false
    resp = json_post("tasks/pushNotification/get", {})
    assert_equal A2A::JsonRpc::ErrorCode::PUSH_NOT_SUPPORTED, resp.dig("error", "code")
  end

  def test_push_delete_returns_not_supported_when_capability_false
    resp = json_post("tasks/pushNotification/delete", {})
    assert_equal A2A::JsonRpc::ErrorCode::PUSH_NOT_SUPPORTED, resp.dig("error", "code")
  end

  def test_push_list_returns_not_supported_when_capability_false
    resp = json_post("tasks/pushNotification/list", {})
    assert_equal A2A::JsonRpc::ErrorCode::PUSH_NOT_SUPPORTED, resp.dig("error", "code")
  end

  # --- push notifications enabled ---

  def test_push_set_returns_true_when_capability_enabled
    resp = json_post("tasks/pushNotification/set", {}, build_app(push_notifications: true))
    assert_nil resp["error"]
    assert_equal true, resp["result"]
  end

  def test_push_get_returns_nil_when_capability_enabled
    resp = json_post("tasks/pushNotification/get", {}, build_app(push_notifications: true))
    assert_nil resp["error"]
    assert_nil resp["result"]
  end

  def test_push_delete_returns_true_when_capability_enabled
    resp = json_post("tasks/pushNotification/delete", {}, build_app(push_notifications: true))
    assert_nil resp["error"]
    assert_equal true, resp["result"]
  end

  def test_push_list_returns_empty_array_when_capability_enabled
    resp = json_post("tasks/pushNotification/list", {}, build_app(push_notifications: true))
    assert_nil resp["error"]
    assert_equal [], resp["result"]
  end
end
