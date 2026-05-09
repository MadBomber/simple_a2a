# frozen_string_literal: true

require "test_helper"
require "async"
require "async/http/endpoint"
require "falcon"
require "socket"

# These executors emit events without sleeping, so streaming completes quickly in tests.

class SSEStreamingExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.start!
    ctx.emit_status

    artifact = A2A::Models::Artifact.new(
      index:      0,
      parts:      [A2A::Models::Part.text("hello world")],
      last_chunk: true
    )
    ctx.emit_artifact(artifact, last_chunk: true)

    ctx.task.complete!
    ctx.emit_status(final: true)
  end
end

class SSEErrorExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.start!
    ctx.emit_status
    raise RuntimeError, "executor blew up"
  end
end

class TestServerAppSSE < Minitest::Test
  def free_port
    s = TCPServer.new(0)
    s.addr[1]
  ensure
    s.close
  end

  def build_app(executor)
    storage  = A2A::Storage::Memory.new
    registry = A2A::Server::BroadcastRegistry.new
    card     = A2A::Models::AgentCard.new(
      name:         "SSETestAgent",
      version:      "1.0",
      capabilities: A2A::Models::AgentCapabilities.new(streaming: true),
      skills:       [A2A::Models::AgentSkill.new(name: "test")],
      interfaces:   [A2A::Models::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
    klass = Class.new(A2A::Server::App)
    klass.configure(agent_card: card, storage: storage, executor: executor, broadcast_registry: registry)
    klass.freeze.app
  end

  # Starts a real Falcon server on a free port, yields the base URL, then stops.
  # Must be called from within a test method (not inside Async) so that the
  # Async block creates a fresh event loop for server + client to share.
  def with_server(app)
    port = free_port
    url  = "http://localhost:#{port}"

    Async do |task|
      endpoint    = Async::HTTP::Endpoint.parse(url)
      server      = Falcon::Server.new(Falcon::Server.middleware(app), endpoint)
      server_task = task.async { server.run }

      # Poll until the server accepts connections (up to 5 s)
      deadline = Time.now + 5
      loop do
        TCPSocket.new("localhost", port).close
        break
      rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Errno::ETIMEDOUT
        raise "SSE test server did not start within 5s" if Time.now > deadline
        task.sleep 0.05
      end

      yield url
    ensure
      server_task&.stop
    end
  end

  def test_subscribe_receives_status_and_artifact_events
    with_server(build_app(SSEStreamingExecutor.new)) do |url|
      events = []
      A2A.sse_client(url: url)
         .send_subscribe(message: A2A::Models::Message.user("go")) { |ev| events << ev }

      status_events   = events.select { |e| e.is_a?(A2A::Models::TaskStatusUpdateEvent) }
      artifact_events = events.select { |e| e.is_a?(A2A::Models::TaskArtifactUpdateEvent) }

      assert_operator status_events.length, :>=, 1
      assert_equal 1, artifact_events.length
      assert_equal "hello world", artifact_events.first.artifact.parts.first.text
    end
  end

  def test_subscribe_final_status_is_completed
    with_server(build_app(SSEStreamingExecutor.new)) do |url|
      events = []
      A2A.sse_client(url: url)
         .send_subscribe(message: A2A::Models::Message.user("go")) { |ev| events << ev }

      final = events
        .select { |e| e.is_a?(A2A::Models::TaskStatusUpdateEvent) && e.final }
        .last
      refute_nil final
      assert_equal "completed", final.status.state
    end
  end

  def test_subscribe_executor_error_emits_sse_error_event
    with_server(build_app(SSEErrorExecutor.new)) do |url|
      events = []
      A2A.sse_client(url: url)
         .send_subscribe(message: A2A::Models::Message.user("go")) { |ev| events << ev }

      # Error events arrive as raw hashes (no matching EVENT_CLASSES entry for error type)
      error_events = events.select { |e| e.is_a?(Hash) && e["error"] }
      refute_empty error_events
      assert_includes error_events.first.dig("error", "message"), "executor blew up"
    end
  end
end
