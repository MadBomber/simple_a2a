# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "async"
require "async/http/endpoint"
require "falcon"
require "socket"

# Emits one status update, pauses to allow a second subscriber to attach,
# then emits an artifact and completes.
class SlowStreamExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.start!
    ctx.emit_status
    sleep(0.3)
    artifact = A2A::Models::Artifact.new(
      index: 0,
      parts: [A2A::Models::Part.text("result")],
      last_chunk: true
    )
    ctx.emit_artifact(artifact, last_chunk: true)
    ctx.task.complete!
    ctx.emit_status(final: true)
  end
end


class TestServerAppResubscribe < Minitest::Test
  include Rack::Test::Methods

  M = A2A::Models

  def build_app(executor = SlowStreamExecutor.new)
    storage  = A2A::Storage::Memory.new
    registry = A2A::Server::BroadcastRegistry.new
    card     = M::AgentCard.new(
      name: "ResubTestAgent",
      version: "1.0",
      capabilities: M::AgentCapabilities.new(streaming: true),
      skills: [M::AgentSkill.new(name: "test")],
      interfaces: [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
    klass = Class.new(A2A::Server::App)
    klass.configure(agent_card: card, storage: storage, executor: executor, broadcast_registry: registry)
    klass.freeze
  end


  def app
    build_app.app
  end


  def json_post(method, params = {})
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params })
    post "/", body, "CONTENT_TYPE" => "application/json"
    JSON.parse(last_response.body)
  end

  # --- Error cases (JSON responses, no SSE) ---

  def test_resubscribe_missing_id_returns_invalid_params
    result = json_post("tasks/resubscribe", {})
    assert_equal(-32_602, result.dig("error", "code"))
  end


  def test_resubscribe_unknown_task_returns_task_not_found
    result = json_post("tasks/resubscribe", { "id" => "no-such-task" })
    assert result.key?("error"), "expected error response"
    assert_includes result.dig("error", "message").to_s.downcase, "not found"
  end


  def test_resubscribe_terminal_task_returns_unsupported_operation
    # Create and complete a task synchronously, then try to resubscribe.
    sync_app = build_app(SSEStreamingExecutor.new).app
    sync_rack = Rack::MockRequest.new(sync_app)

    msg_params = { "message" => { "role" => "user", "parts" => [{ "kind" => "text", "text" => "go" }] } }
    send_body = JSON.generate({
                                "jsonrpc" => "2.0", "id" => 1, "method" => "tasks/send",
                                "params" => msg_params
                              })
    send_resp = JSON.parse(sync_rack.post("/", input: send_body, "CONTENT_TYPE" => "application/json").body)
    task_id   = send_resp.dig("result", "id")
    refute_nil task_id

    resub_body = JSON.generate({ "jsonrpc" => "2.0", "id" => 2, "method" => "tasks/resubscribe",
                                 "params" => { "id" => task_id } })
    resub_resp = JSON.parse(sync_rack.post("/", input: resub_body,
                                                "CONTENT_TYPE" => "application/json").body)

    assert resub_resp.key?("error"), "expected error response"
    assert_includes resub_resp.dig("error", "message").to_s, "terminal"
  end

  # --- Happy path (real Falcon server) ---

  def free_port
    s = TCPServer.new(0)
    s.addr[1]
  ensure
    s.close
  end


  def with_server(rack_app)
    port = free_port
    url  = "http://localhost:#{port}"

    Async do |task|
      endpoint    = Async::HTTP::Endpoint.parse(url)
      server      = Falcon::Server.new(Falcon::Server.middleware(rack_app), endpoint)
      server_task = task.async { server.run }

      deadline = Time.now + 5
      loop do
        TCPSocket.new("localhost", port).close
        break
      rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Errno::ETIMEDOUT
        raise "Server did not start within 5s" if Time.now > deadline

        task.sleep 0.05
      end

      yield url, task
    ensure
      server_task&.stop
    end
  end


  def test_resubscribe_first_event_is_task_snapshot
    with_server(build_app.app) do |url, task|
      captured_task_id = nil
      second_sub_events = []

      first_task = task.async do
        A2A.sse_client(url: url)
           .send_subscribe(message: M::Message.user("go")) do |ev|
          captured_task_id ||= ev.task_id if ev.respond_to?(:task_id)
        end
      end

      loop do
        break if captured_task_id

        task.sleep(0.01)
      end

      A2A.sse_client(url: url)
         .resubscribe(task_id: captured_task_id) { |ev| second_sub_events << ev }

      first_task.wait

      # First event from resubscribe is the Task snapshot — no type field, comes back as Hash
      snapshot = second_sub_events.first
      assert_instance_of Hash, snapshot
      assert_equal captured_task_id, snapshot["id"]
    end
  end


  def test_resubscribe_receives_subsequent_events
    with_server(build_app.app) do |url, task|
      captured_task_id = nil
      second_sub_events = []

      first_task = task.async do
        A2A.sse_client(url: url)
           .send_subscribe(message: M::Message.user("go")) do |ev|
          captured_task_id ||= ev.task_id if ev.respond_to?(:task_id)
        end
      end

      loop do
        break if captured_task_id

        task.sleep(0.01)
      end

      A2A.sse_client(url: url)
         .resubscribe(task_id: captured_task_id) { |ev| second_sub_events << ev }

      first_task.wait

      final = second_sub_events
              .select { |e| e.is_a?(M::TaskStatusUpdateEvent) && e.final? }
              .last
      refute_nil final, "expected a final status event from resubscribe"
      assert_equal "completed", final.status.state
    end
  end
end
