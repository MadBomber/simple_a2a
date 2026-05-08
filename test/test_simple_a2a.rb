# frozen_string_literal: true

require "test_helper"

class TestA2A < Minitest::Test
  M = A2A::Models

  def minimal_card(name = "TestAgent")
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

  def test_that_it_has_a_version_number
    refute_nil ::A2A::VERSION
  end

  def test_logger_accessor
    A2A.logger = nil
    assert_nil A2A.logger
  end

  def test_server_factory_returns_server_base
    server = A2A.server(agent_card: minimal_card, executor: NoopExecutor.new)
    assert_kind_of A2A::Server::Base, server
  end

  def test_multi_server_factory_returns_multi_agent
    multi = A2A.multi_server(
      agents: {
        "/test" => { agent_card: minimal_card, executor: NoopExecutor.new }
      }
    )
    assert_kind_of A2A::Server::MultiAgent, multi
  end

  def test_client_factory_returns_client_base
    client = A2A.client(url: "http://localhost:9292")
    assert_kind_of A2A::Client::Base, client
  end

  def test_sse_client_factory_returns_sse_client
    client = A2A.sse_client(url: "http://localhost:9292")
    assert_kind_of A2A::Client::SSE, client
  end
end
