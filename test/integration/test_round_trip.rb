# frozen_string_literal: true

require "test_helper"
require "rack/test"

class EchoProcessExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    input = ctx.message.parts.map { |p| p.respond_to?(:text) ? p.text : "" }.join
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "reply",
        parts: [A2A::Models::Part.text("Processed: #{input}")]
      )
    ])
  end
end

class TestIntegration < Minitest::Test
  include Rack::Test::Methods

  M = A2A::Models

  def app
    storage  = A2A::Storage::Memory.new
    executor = EchoProcessExecutor.new
    router   = A2A::Server::EventRouter.new
    card     = M::AgentCard.new(
      name:         "integration-agent",
      version:      "1.0",
      capabilities: M::AgentCapabilities.new,
      skills:       [M::AgentSkill.new(name: "echo")],
      interfaces:   [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )

    app_class = Class.new(A2A::Server::App)
    app_class.configure(
      agent_card:   card,
      storage:      storage,
      executor:     executor,
      event_router: router
    )
    app_class.freeze.app
  end

  def rpc(method, params = {})
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params })
    post "/", body, "CONTENT_TYPE" => "application/json"
    JSON.parse(last_response.body)
  end

  def test_agent_card_discoverable
    get "/agentCard"
    assert last_response.ok?
    card = JSON.parse(last_response.body)
    assert_equal "integration-agent", card["name"]
    assert_equal "1.0",               card["version"]
  end

  def test_full_send_and_retrieve_round_trip
    message = M::Message.user("hello world")
    resp    = rpc("tasks/send", { "message" => message.to_h })
    assert_nil resp["error"], "Expected no error, got: #{resp["error"]&.inspect}"

    task = resp["result"]
    assert_equal "completed",  task["status"]["state"]
    assert_equal 1,            task["artifacts"].length
    assert_includes task["artifacts"][0]["parts"][0]["text"], "hello world"
  end

  def test_task_persists_after_send
    message = M::Message.user("persist me")
    send_resp = rpc("tasks/send", { "message" => message.to_h })
    task_id   = send_resp["result"]["id"]
    refute_nil task_id

    get_resp = rpc("tasks/get", { "id" => task_id })
    assert_nil get_resp["error"]
    assert_equal task_id, get_resp["result"]["id"]
  end

  def test_task_appears_in_list
    message = M::Message.user("list me")
    rpc("tasks/send", { "message" => message.to_h })

    list_resp = rpc("tasks/list", {})
    assert_nil list_resp["error"]
    assert list_resp["result"].is_a?(Array)
    assert_operator list_resp["result"].length, :>=, 1
  end

  def test_cancel_completed_task_returns_not_cancelable
    message = M::Message.user("cancel me")
    send_resp = rpc("tasks/send", { "message" => message.to_h })
    task_id   = send_resp["result"]["id"]

    cancel_resp = rpc("tasks/cancel", { "id" => task_id })
    refute_nil cancel_resp["error"]
    assert_equal A2A::JsonRpc::ErrorCode::TASK_NOT_CANCELABLE, cancel_resp["error"]["code"]
  end

  def test_version_header_negotiation
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => "tasks/list", "params" => {} })
    post "/", body, "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0"
    resp = JSON.parse(last_response.body)
    assert_nil resp["error"]

    post "/", body, "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "99.0"
    resp = JSON.parse(last_response.body)
    assert_equal A2A::JsonRpc::ErrorCode::VERSION_NOT_SUPPORTED, resp["error"]["code"]
  end

  def test_unknown_method_returns_method_not_found
    resp = rpc("tasks/doesNotExist", {})
    assert_equal A2A::JsonRpc::ErrorCode::METHOD_NOT_FOUND, resp["error"]["code"]
  end

  def test_invalid_json_returns_parse_error
    post "/", "{ this is not json }", "CONTENT_TYPE" => "application/json"
    resp = JSON.parse(last_response.body)
    assert_equal A2A::JsonRpc::ErrorCode::PARSE_ERROR, resp["error"]["code"]
  end

  def test_factory_method_creates_client
    client = A2A.client(url: "http://localhost:9292")
    assert_kind_of A2A::Client::Base, client
  end

  def test_factory_method_creates_sse_client
    client = A2A.sse_client(url: "http://localhost:9292")
    assert_kind_of A2A::Client::SSE, client
  end
end
