# frozen_string_literal: true

require "test_helper"
require "rack/test"

class EchoExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(parts: [A2A::Models::Part.text("echo")])
    ])
  end
end

class TestServerApp < Minitest::Test
  include Rack::Test::Methods

  def app
    storage  = A2A::Storage::Memory.new
    executor = EchoExecutor.new
    router   = A2A::Server::EventRouter.new
    card     = A2A::Models::AgentCard.new(
      name:         "TestAgent",
      version:      "1.0",
      capabilities: A2A::Models::AgentCapabilities.new,
      skills:       [A2A::Models::AgentSkill.new(name: "echo")],
      interfaces:   [A2A::Models::AgentInterface.new(
        type: "json-rpc", url: "http://localhost/a2a", version: "1.0"
      )]
    )

    # Use a fresh App subclass per test to avoid configure state leakage
    app_class = Class.new(A2A::Server::App)
    app_class.configure(
      agent_card:   card,
      storage:      storage,
      executor:     executor,
      event_router: router
    )
    app_class.freeze.app
  end

  def json_post(method, params = {})
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params })
    post "/", body, "CONTENT_TYPE" => "application/json"
  end

  def parsed_response
    JSON.parse(last_response.body)
  end

  # --- Agent Card ---

  def test_get_agent_card
    get "/agentCard"
    assert last_response.ok?
    card = parsed_response
    assert_equal "TestAgent", card["name"]
    assert_equal "1.0", card["version"]
  end

  # --- tasks/send ---

  def test_tasks_send_returns_completed_task
    msg = A2A::Models::Message.user("hello").to_h
    json_post("tasks/send", { "message" => msg })
    assert last_response.ok?
    resp = parsed_response
    assert_equal 1, resp["id"]
    assert_nil resp["error"]
    assert_equal "completed", resp["result"]["status"]["state"]
    assert_equal 1, resp["result"]["artifacts"].length
  end

  def test_tasks_send_missing_message_returns_error
    json_post("tasks/send", {})
    resp = parsed_response
    refute_nil resp["error"]
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_PARAMS, resp["error"]["code"]
  end

  # --- tasks/get ---

  def test_tasks_get_returns_task
    msg = A2A::Models::Message.user("hello").to_h
    json_post("tasks/send", { "message" => msg })
    task_id = parsed_response.dig("result", "id")

    json_post("tasks/get", { "id" => task_id })
    resp = parsed_response
    assert_nil resp["error"]
    assert_equal task_id, resp["result"]["id"]
  end

  def test_tasks_get_missing_id_returns_error
    json_post("tasks/get", {})
    resp = parsed_response
    refute_nil resp["error"]
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_PARAMS, resp["error"]["code"]
  end

  def test_tasks_get_unknown_id_returns_not_found
    json_post("tasks/get", { "id" => "no-such-task" })
    resp = parsed_response
    refute_nil resp["error"]
    assert_equal A2A::JsonRpc::ErrorCode::TASK_NOT_FOUND, resp["error"]["code"]
  end

  # --- tasks/list ---

  def test_tasks_list_returns_all_tasks
    msg = A2A::Models::Message.user("a").to_h
    json_post("tasks/send", { "message" => msg })
    json_post("tasks/list", {})
    resp = parsed_response
    assert_nil resp["error"]
    assert resp["result"].is_a?(Array)
    assert_operator resp["result"].length, :>=, 1
  end

  # --- tasks/cancel ---

  def test_tasks_cancel_completed_task_returns_not_cancelable
    msg = A2A::Models::Message.user("hello").to_h
    json_post("tasks/send", { "message" => msg })
    task_id = parsed_response.dig("result", "id")

    json_post("tasks/cancel", { "id" => task_id })
    resp = parsed_response
    refute_nil resp["error"]
    assert_equal A2A::JsonRpc::ErrorCode::TASK_NOT_CANCELABLE, resp["error"]["code"]
  end

  # --- unknown method ---

  def test_unknown_method_returns_method_not_found
    json_post("tasks/unknown", {})
    resp = parsed_response
    assert_equal A2A::JsonRpc::ErrorCode::METHOD_NOT_FOUND, resp["error"]["code"]
  end

  # --- parse errors ---

  def test_invalid_json_returns_parse_error
    post "/", "not json", "CONTENT_TYPE" => "application/json"
    resp = parsed_response
    assert_equal A2A::JsonRpc::ErrorCode::PARSE_ERROR, resp["error"]["code"]
  end

  def test_missing_jsonrpc_field_returns_invalid_request
    body = JSON.generate({ "id" => 1, "method" => "tasks/list" })
    post "/", body, "CONTENT_TYPE" => "application/json"
    resp = parsed_response
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_REQUEST, resp["error"]["code"]
  end

  # --- version header ---

  def test_unsupported_version_header_returns_error
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => "tasks/list" })
    post "/", body, "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "99.0"
    resp = parsed_response
    assert_equal A2A::JsonRpc::ErrorCode::VERSION_NOT_SUPPORTED, resp["error"]["code"]
  end

  def test_supported_version_header_passes
    msg = A2A::Models::Message.user("hi").to_h
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => "tasks/send", "params" => { "message" => msg } })
    post "/", body, "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0"
    resp = parsed_response
    assert_nil resp["error"]
  end
end
