# frozen_string_literal: true

require "test_helper"

class TestClientSSE < Minitest::Test
  def setup
    @client = A2A::Client::SSE.new(url: "http://localhost:9292")
  end

  def status_update_event_hash(state: "working", final: false)
    {
      "type"      => "TaskStatusUpdateEvent",
      "taskId"    => "t-1",
      "contextId" => "c-1",
      "status"    => { "state" => state, "timestamp" => "2026-01-01T00:00:00Z" },
      "final"     => final
    }
  end

  def artifact_update_event_hash
    {
      "type"      => "TaskArtifactUpdateEvent",
      "taskId"    => "t-1",
      "contextId" => "c-1",
      "artifact"  => { "parts" => [{ "kind" => "text", "text" => "hello" }] },
      "final"     => false
    }
  end

  # Fake response body that yields chunks via #each (matches async/http body interface)
  def fake_response(sse_body, chunk_size: 16)
    chunks = sse_body.chars.each_slice(chunk_size).map(&:join)
    body   = Object.new
    body.define_singleton_method(:each) { |&b| chunks.each(&b) }
    resp   = Object.new
    resp.define_singleton_method(:body) { body }
    resp
  end

  # --- parse_sse_event ---

  def test_parse_sse_event_status_update
    data      = JSON.generate({ "result" => status_update_event_hash })
    event_str = "data: #{data}"
    event     = @client.send(:parse_sse_event, event_str)
    assert_kind_of A2A::Models::TaskStatusUpdateEvent, event
    assert_equal "t-1", event.task_id
  end

  def test_parse_sse_event_artifact_update
    data      = JSON.generate({ "result" => artifact_update_event_hash })
    event_str = "data: #{data}"
    event     = @client.send(:parse_sse_event, event_str)
    assert_kind_of A2A::Models::TaskArtifactUpdateEvent, event
    assert_equal "t-1", event.task_id
  end

  def test_parse_sse_event_returns_hash_for_unknown_type
    data      = JSON.generate({ "result" => { "type" => "UnknownEvent", "foo" => "bar" } })
    event_str = "data: #{data}"
    event     = @client.send(:parse_sse_event, event_str)
    assert_kind_of Hash, event
  end

  def test_parse_sse_event_returns_nil_for_no_data
    event = @client.send(:parse_sse_event, "event: ping\n")
    assert_nil event
  end

  def test_parse_sse_event_returns_nil_for_invalid_json
    event = @client.send(:parse_sse_event, "data: not-json")
    assert_nil event
  end

  def test_parse_sse_event_ignores_comment_lines
    data      = JSON.generate({ "result" => status_update_event_hash })
    event_str = ": keep-alive\ndata: #{data}"
    event     = @client.send(:parse_sse_event, event_str)
    assert_kind_of A2A::Models::TaskStatusUpdateEvent, event
  end

  # --- parse_sse_stream ---

  def test_parse_sse_stream_yields_events
    ev1 = JSON.generate({ "result" => status_update_event_hash(state: "working") })
    ev2 = JSON.generate({ "result" => status_update_event_hash(state: "completed", final: true) })
    sse_body = "data: #{ev1}\n\ndata: #{ev2}\n\n"

    events = []
    @client.send(:parse_sse_stream, fake_response(sse_body)) { |ev| events << ev }

    assert_equal 2, events.length
    assert_kind_of A2A::Models::TaskStatusUpdateEvent, events[0]
    assert_kind_of A2A::Models::TaskStatusUpdateEvent, events[1]
    assert_equal "working",   events[0].status.state
    assert_equal "completed", events[1].status.state
  end

  def test_parse_sse_stream_handles_chunked_delivery
    data     = JSON.generate({ "result" => status_update_event_hash })
    sse_body = "data: #{data}\n\n"

    events = []
    @client.send(:parse_sse_stream, fake_response(sse_body, chunk_size: 5)) { |ev| events << ev }

    assert_equal 1, events.length
    assert_kind_of A2A::Models::TaskStatusUpdateEvent, events.first
  end

  def test_parse_sse_stream_skips_nil_events
    sse_body = ": keep-alive\n\ndata: bad-json\n\n"

    events = []
    @client.send(:parse_sse_stream, fake_response(sse_body)) { |ev| events << ev }
    assert_equal 0, events.length
  end
end
