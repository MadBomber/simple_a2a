# frozen_string_literal: true

require "test_helper"
require "rack/test"

class PushTestExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.complete!
  end
end

class TestServerAppPush < Minitest::Test
  include Rack::Test::Methods

  M = A2A::Models

  def build_app(push_notifications:)
    @storage = A2A::Storage::Memory.new
    card     = M::AgentCard.new(
      name:         "PushTestAgent",
      version:      "1.0",
      capabilities: M::AgentCapabilities.new(push_notifications: push_notifications),
      skills:       [M::AgentSkill.new(name: "test")],
      interfaces:   [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
    klass = Class.new(A2A::Server::App)
    klass.configure(
      agent_card:         card,
      storage:            @storage,
      executor:           PushTestExecutor.new,
      broadcast_registry: A2A::Server::BroadcastRegistry.new
    )
    klass.freeze.app
  end

  def push_app = build_app(push_notifications: true)
  def app      = build_app(push_notifications: false)

  def json_post(method, params = {}, rack_app = app)
    @_rack_app = rack_app
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params })
    post "/", body, "CONTENT_TYPE" => "application/json"
    JSON.parse(last_response.body)
  end

  alias original_app app
  def app = @_rack_app || original_app

  def make_task(app_to_use)
    resp = json_post("tasks/send", { "message" => { "role" => "user", "parts" => [{ "kind" => "text", "text" => "hi" }] } }, app_to_use)
    resp.dig("result", "id")
  end

  # ── push notifications disabled ──────────────────────────────────────────────

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

  # ── parameter validation ─────────────────────────────────────────────────────

  def test_push_set_missing_id_returns_invalid_params
    the_app = push_app
    resp = json_post("tasks/pushNotification/set", {}, the_app)
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_PARAMS, resp.dig("error", "code")
  end

  def test_push_set_missing_config_returns_invalid_params
    the_app = push_app
    task_id = make_task(the_app)
    resp = json_post("tasks/pushNotification/set", { "id" => task_id }, the_app)
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_PARAMS, resp.dig("error", "code")
  end

  def test_push_set_missing_webhook_url_returns_invalid_params
    the_app = push_app
    task_id = make_task(the_app)
    resp = json_post("tasks/pushNotification/set",
                     { "id" => task_id, "pushNotificationConfig" => {} },
                     the_app)
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_PARAMS, resp.dig("error", "code")
  end

  def test_push_set_unknown_task_returns_not_found
    the_app = push_app
    resp = json_post("tasks/pushNotification/set",
                     { "id" => "nonexistent", "pushNotificationConfig" => { "webhookUrl" => "http://h/cb" } },
                     the_app)
    assert_equal A2A::JsonRpc::ErrorCode::TASK_NOT_FOUND, resp.dig("error", "code")
  end

  def test_push_get_missing_id_returns_invalid_params
    the_app = push_app
    resp = json_post("tasks/pushNotification/get", {}, the_app)
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_PARAMS, resp.dig("error", "code")
  end

  def test_push_delete_missing_id_returns_invalid_params
    the_app = push_app
    resp = json_post("tasks/pushNotification/delete", {}, the_app)
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_PARAMS, resp.dig("error", "code")
  end

  # ── CRUD happy path ──────────────────────────────────────────────────────────

  def test_push_set_stores_config_and_returns_task_push_notification_config
    the_app = push_app
    task_id = make_task(the_app)

    resp = json_post("tasks/pushNotification/set",
                     { "id" => task_id, "pushNotificationConfig" => { "webhookUrl" => "https://example.com/cb" } },
                     the_app)

    assert_nil resp["error"], resp["error"].inspect
    result = resp["result"]
    assert_equal task_id, result["id"]
    assert_equal "https://example.com/cb", result.dig("pushNotificationConfig", "webhookUrl")
  end

  def test_push_get_returns_nil_when_no_config_stored
    the_app = push_app
    task_id = make_task(the_app)

    resp = json_post("tasks/pushNotification/get", { "id" => task_id }, the_app)
    assert_nil resp["error"]
    assert_nil resp["result"]
  end

  def test_push_get_returns_config_after_set
    the_app = push_app
    task_id = make_task(the_app)

    json_post("tasks/pushNotification/set",
              { "id" => task_id, "pushNotificationConfig" => { "webhookUrl" => "https://example.com/cb" } },
              the_app)

    resp = json_post("tasks/pushNotification/get", { "id" => task_id }, the_app)
    assert_nil resp["error"]
    assert_equal task_id, resp.dig("result", "id")
    assert_equal "https://example.com/cb", resp.dig("result", "pushNotificationConfig", "webhookUrl")
  end

  def test_push_set_overwrites_existing_config
    the_app = push_app
    task_id = make_task(the_app)

    json_post("tasks/pushNotification/set",
              { "id" => task_id, "pushNotificationConfig" => { "webhookUrl" => "https://old.example.com/cb" } },
              the_app)

    json_post("tasks/pushNotification/set",
              { "id" => task_id, "pushNotificationConfig" => { "webhookUrl" => "https://new.example.com/cb" } },
              the_app)

    resp = json_post("tasks/pushNotification/get", { "id" => task_id }, the_app)
    assert_equal "https://new.example.com/cb", resp.dig("result", "pushNotificationConfig", "webhookUrl")
  end

  def test_push_delete_removes_config
    the_app = push_app
    task_id = make_task(the_app)

    json_post("tasks/pushNotification/set",
              { "id" => task_id, "pushNotificationConfig" => { "webhookUrl" => "https://example.com/cb" } },
              the_app)
    json_post("tasks/pushNotification/delete", { "id" => task_id }, the_app)

    resp = json_post("tasks/pushNotification/get", { "id" => task_id }, the_app)
    assert_nil resp["result"]
  end

  def test_push_delete_returns_null_result
    the_app = push_app
    task_id = make_task(the_app)

    resp = json_post("tasks/pushNotification/delete", { "id" => task_id }, the_app)
    assert_nil resp["error"]
    assert_nil resp["result"]
  end

  def test_push_list_returns_empty_when_no_configs
    the_app = push_app
    resp = json_post("tasks/pushNotification/list", {}, the_app)
    assert_nil resp["error"]
    assert_equal [], resp["result"]
  end

  def test_push_list_returns_all_stored_configs
    the_app = push_app
    task_id1 = make_task(the_app)
    task_id2 = make_task(the_app)

    json_post("tasks/pushNotification/set",
              { "id" => task_id1, "pushNotificationConfig" => { "webhookUrl" => "https://a.example.com/cb" } },
              the_app)
    json_post("tasks/pushNotification/set",
              { "id" => task_id2, "pushNotificationConfig" => { "webhookUrl" => "https://b.example.com/cb" } },
              the_app)

    resp = json_post("tasks/pushNotification/list", {}, the_app)
    assert_nil resp["error"]
    list = resp["result"]
    assert_equal 2, list.length
    ids   = list.map { |e| e["id"] }
    urls  = list.map { |e| e.dig("pushNotificationConfig", "webhookUrl") }
    assert_includes ids, task_id1
    assert_includes ids, task_id2
    assert_includes urls, "https://a.example.com/cb"
    assert_includes urls, "https://b.example.com/cb"
  end
end
