# frozen_string_literal: true

require "test_helper"
require "rack/test"

class TestServerBase < Minitest::Test
  include Rack::Test::Methods

  M = A2A::Models

  def minimal_card(name = "BaseTestAgent")
    M::AgentCard.new(
      name:         name,
      version:      "1.0",
      capabilities: M::AgentCapabilities.new,
      skills:       [M::AgentSkill.new(name: "test")],
      interfaces:   [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
  end

  class NoopExecutor < A2A::Server::AgentExecutor
    def call(ctx) = nil
  end

  def build_server(**opts)
    A2A::Server::Base.new(
      agent_card: minimal_card,
      executor:   NoopExecutor.new,
      **opts
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
end
