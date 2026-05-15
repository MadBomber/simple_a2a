# frozen_string_literal: true

require "test_helper"
require "rack/test"

class TestServerBase < Minitest::Test
  include Rack::Test::Methods

  M = A2A::Models

  def minimal_card(name = "BaseTestAgent")
    M::AgentCard.new(
      name: name,
      version: "1.0",
      capabilities: M::AgentCapabilities.new,
      skills: [M::AgentSkill.new(name: "test")],
      interfaces: [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
  end


  class NoopExecutor < A2A::Server::AgentExecutor
    def call(_ctx) = nil
  end


  def build_server(**)
    A2A::Server::Base.new(
      agent_card: minimal_card,
      executor: NoopExecutor.new,
      **
    )
  end


  def app
    build_server.rack_app
  end


  def test_rack_app_returns_callable
    result = build_server.rack_app
    assert_respond_to result, :call
  end


  def test_rack_app_serves_agent_card
    get "/agentCard"
    assert last_response.ok?
    parsed = JSON.parse(last_response.body)
    assert_equal "BaseTestAgent", parsed["name"]
  end


  def test_rack_app_uses_provided_storage
    storage = A2A::Storage::Memory.new
    server  = build_server(storage: storage)
    assert_respond_to server.rack_app, :call
  end


  def test_rack_app_is_independent_per_call
    s1 = build_server.rack_app
    s2 = build_server.rack_app
    refute_same s1, s2
  end


  def test_accessors
    storage  = A2A::Storage::Memory.new
    executor = NoopExecutor.new
    server   = A2A::Server::Base.new(agent_card: minimal_card, executor: executor, storage: storage)
    assert_equal minimal_card, server.agent_card
    assert_equal executor, server.executor
    assert_equal storage, server.storage
    assert_nil server.push_sender
  end


  def test_custom_push_config_store_is_forwarded_to_rack_app
    store  = A2A::Server::PushConfigStore.new
    card   = M::AgentCard.new(
      name: "PushAgent",
      version: "1.0",
      capabilities: M::AgentCapabilities.new(push_notifications: true),
      skills: [M::AgentSkill.new(name: "test")],
      interfaces: [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
    server = A2A::Server::Base.new(agent_card: card, executor: NoopExecutor.new, push_config_store: store)

    session = Rack::Test::Session.new(Rack::MockSession.new(server.rack_app))

    # Seed a config directly into our store instance.
    config = A2A::Models::PushNotificationConfig.new(
      task_id: "task-1",
      webhook_url: "http://example.com/hook"
    )
    store.set("task-1", config)

    # The rack app's pushNotification/list should see the same store.
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1,
                           "method" => "tasks/pushNotification/list", "params" => {} })
    resp = JSON.parse(session.post("/", body, "CONTENT_TYPE" => "application/json").body)

    assert_nil resp["error"]
    assert_equal 1, resp["result"].length
    assert_equal "http://example.com/hook",
                 resp["result"].first.dig("pushNotificationConfig", "webhookUrl")
  end
end
