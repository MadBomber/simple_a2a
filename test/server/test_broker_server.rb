# frozen_string_literal: true

require "test_helper"
require "rack/test"

class BrokerEchoExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.complete!(artifacts: [
                         A2A::Models::Artifact.new(parts: [A2A::Models::Part.text("echo")])
                       ])
  end
end


class TestBrokerServer < Minitest::Test
  include Rack::Test::Methods

  M = A2A::Models

  def build_card(name, description: "A test agent", skill_name: "test")
    M::AgentCard.new(
      name: name,
      description: description,
      version: "1.0",
      capabilities: M::AgentCapabilities.new,
      skills: [M::AgentSkill.new(name: skill_name)],
      interfaces: [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
  end


  def app
    broker = A2A::Server::BrokerServer.new(
      agents: {
        "/agents/weather" => {
          agent_card: build_card("WeatherAgent", description: "Provides weather forecasts",
                                                 skill_name: "forecast"), executor: BrokerEchoExecutor.new
        },
        "/agents/billing" => {
          agent_card: build_card("BillingAgent", description: "Handles billing and invoices",
                                                 skill_name: "invoice"),  executor: BrokerEchoExecutor.new
        }
      }
    )
    broker.send(:rack_app)
  end


  def json_post(path, method, params = {})
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params })
    post path, body, "CONTENT_TYPE" => "application/json"
    JSON.parse(last_response.body)
  end

  # --- well-known route ---

  def test_well_known_agent_card_returns_broker_card
    get "/.well-known/agent-card.json"
    assert last_response.ok?, "Expected 200, got #{last_response.status}"
    card = JSON.parse(last_response.body)
    assert_equal "Service Broker", card["name"]
  end


  def test_well_known_content_type_is_json
    get "/.well-known/agent-card.json"
    assert_includes last_response.content_type, "application/json"
  end

  # --- legacy agentCard route on broker ---

  def test_legacy_agent_card_route_also_returns_broker_card
    get "/agentCard"
    assert last_response.ok?
    assert_equal "Service Broker", JSON.parse(last_response.body)["name"]
  end

  # --- sub-agent card routes ---

  def test_sub_agent_card_returns_correct_name
    get "/agents/weather/agentCard"
    assert last_response.ok?
    assert_equal "WeatherAgent", JSON.parse(last_response.body)["name"]
  end


  def test_sub_agent_well_known_card_is_accessible
    get "/agents/weather/.well-known/agent-card.json"
    assert last_response.ok?
    assert_equal "WeatherAgent", JSON.parse(last_response.body)["name"]
  end

  # --- default broker card content ---

  def test_default_broker_card_has_routing_skill
    get "/.well-known/agent-card.json"
    card = JSON.parse(last_response.body)
    skill_names = card["skills"].map { |s| s["name"] }
    assert_includes skill_names, "Agent Matcher"
  end

  # --- broker executor ranking ---

  def test_broker_returns_matched_agents_as_artifact
    msg  = M::Message.user("I need a weather forecast").to_h
    resp = json_post("/", "tasks/send", { "message" => msg })
    assert_nil resp["error"], resp.inspect
    assert_equal "completed", resp.dig("result", "status", "state")
    artifacts = resp.dig("result", "artifacts")
    refute_empty artifacts
  end


  def test_broker_ranks_weather_agent_first_for_weather_query
    msg  = M::Message.user("I need a weather forecast").to_h
    resp = json_post("/", "tasks/send", { "message" => msg })
    matches = resp.dig("result", "artifacts", 0, "parts", 0, "data")
    assert_kind_of Array, matches
    assert_equal "WeatherAgent", matches.first["name"]
  end


  def test_broker_ranks_billing_agent_first_for_billing_query
    msg  = M::Message.user("I need an invoice").to_h
    resp = json_post("/", "tasks/send", { "message" => msg })
    matches = resp.dig("result", "artifacts", 0, "parts", 0, "data")
    assert_kind_of Array, matches
    assert_equal "BillingAgent", matches.first["name"]
  end


  def test_broker_returns_all_agents_for_empty_message
    msg  = M::Message.user("").to_h
    resp = json_post("/", "tasks/send", { "message" => msg })
    matches = resp.dig("result", "artifacts", 0, "parts", 0, "data")
    assert_equal 2, matches.length
  end


  def test_broker_returns_empty_array_for_unrecognised_query
    msg  = M::Message.user("xyzzy plugh").to_h
    resp = json_post("/", "tasks/send", { "message" => msg })
    matches = resp.dig("result", "artifacts", 0, "parts", 0, "data")
    assert_kind_of Array, matches
    assert_empty matches
  end

  # --- sub-agent task execution ---

  def test_sub_agent_executes_tasks_independently
    msg  = M::Message.user("hello").to_h
    resp = json_post("/agents/weather", "tasks/send", { "message" => msg })
    assert_nil resp["error"]
    assert_equal "completed", resp.dig("result", "status", "state")
  end


  def test_sub_agent_tasks_are_isolated
    msg     = M::Message.user("hello").to_h
    resp    = json_post("/agents/weather", "tasks/send", { "message" => msg })
    task_id = resp.dig("result", "id")

    not_found = json_post("/agents/billing", "tasks/get", { "id" => task_id })
    refute_nil not_found["error"]
    assert_equal A2A::JsonRpc::ErrorCode::TASK_NOT_FOUND, not_found["error"]["code"]
  end

  # --- custom broker ---

  def test_custom_broker_card_is_used_when_provided
    custom_card = build_card("CustomBroker", description: "My custom broker")
    broker = A2A::Server::BrokerServer.new(
      agents: { "/agents/x" => { agent_card: build_card("XAgent"), executor: BrokerEchoExecutor.new } },
      broker_card: custom_card
    )
    rack = broker.send(:rack_app)
    session = Rack::MockRequest.new(rack)
    response = session.get("/.well-known/agent-card.json")
    assert_equal 200, response.status
    assert_equal "CustomBroker", JSON.parse(response.body)["name"]
  end


  def test_custom_broker_executor_is_used_when_provided
    invoked = false
    custom_exec = Class.new(A2A::Server::AgentExecutor) do
      define_method(:call) do |ctx|
        invoked = true
        ctx.task.complete!
      end
    end.new

    broker = A2A::Server::BrokerServer.new(
      agents: { "/agents/x" => { agent_card: build_card("XAgent"),
                                 executor: BrokerEchoExecutor.new } },
      broker_executor: custom_exec
    )
    rack    = broker.send(:rack_app)
    session = Rack::MockRequest.new(rack)
    body    = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => "tasks/send",
                              "params" => { "message" => M::Message.user("hi").to_h } })
    session.post("/", input: body, "CONTENT_TYPE" => "application/json")
    assert invoked, "Custom broker executor was not called"
  end

  # --- A2A convenience method ---

  def test_a2a_broker_server_returns_broker_server_instance
    instance = A2A.broker_server(
      agents: { "/agents/x" => { agent_card: build_card("XAgent"), executor: BrokerEchoExecutor.new } }
    )
    assert_instance_of A2A::Server::BrokerServer, instance
  end
end
