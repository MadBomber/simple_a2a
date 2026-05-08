# frozen_string_literal: true

require "test_helper"
require "rack/test"

class MultiAgentEchoExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(parts: [A2A::Models::Part.text("echo")])
    ])
  end
end

class TestMultiAgent < Minitest::Test
  include Rack::Test::Methods

  M = A2A::Models

  def build_card(name)
    M::AgentCard.new(
      name:         name,
      version:      "1.0",
      capabilities: M::AgentCapabilities.new,
      skills:       [M::AgentSkill.new(name: "test")],
      interfaces:   [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
  end

  def app
    multi = A2A::Server::MultiAgent.new(
      agents: {
        "/alpha" => { agent_card: build_card("AlphaAgent"), executor: MultiAgentEchoExecutor.new },
        "/beta"  => { agent_card: build_card("BetaAgent"),  executor: MultiAgentEchoExecutor.new }
      }
    )
    multi.send(:rack_app)
  end

  def json_post(path, method, params = {})
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params })
    post path, body, "CONTENT_TYPE" => "application/json"
    JSON.parse(last_response.body)
  end

  def test_alpha_agent_card_returns_correct_name
    get "/alpha/agentCard"
    assert last_response.ok?
    assert_equal "AlphaAgent", JSON.parse(last_response.body)["name"]
  end

  def test_beta_agent_card_returns_correct_name
    get "/beta/agentCard"
    assert last_response.ok?
    assert_equal "BetaAgent", JSON.parse(last_response.body)["name"]
  end

  def test_tasks_are_isolated_between_agents
    msg  = M::Message.user("hello").to_h
    resp = json_post("/alpha", "tasks/send", { "message" => msg })
    task_id = resp.dig("result", "id")
    refute_nil task_id

    # Retrievable on the originating agent
    ok = json_post("/alpha", "tasks/get", { "id" => task_id })
    assert_nil ok["error"]

    # NOT retrievable on the other agent — different storage
    not_found = json_post("/beta", "tasks/get", { "id" => task_id })
    refute_nil not_found["error"]
    assert_equal A2A::JsonRpc::ErrorCode::TASK_NOT_FOUND, not_found["error"]["code"]
  end

  def test_unknown_path_returns_404
    get "/unknown/agentCard"
    assert_equal 404, last_response.status
  end

  def test_both_agents_can_execute_tasks_independently
    msg = M::Message.user("hello").to_h

    resp_alpha = json_post("/alpha", "tasks/send", { "message" => msg })
    resp_beta  = json_post("/beta",  "tasks/send", { "message" => msg })

    assert_nil resp_alpha["error"]
    assert_nil resp_beta["error"]
    assert_equal "completed", resp_alpha.dig("result", "status", "state")
    assert_equal "completed", resp_beta.dig("result", "status", "state")
    refute_equal resp_alpha.dig("result", "id"), resp_beta.dig("result", "id")
  end
end
