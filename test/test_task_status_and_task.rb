# frozen_string_literal: true

require "test_helper"

class TestTaskStatus < Minitest::Test
  def test_required_state
    ts = A2A::Models::TaskStatus.new(state: "working")
    assert_equal "working", ts.state
  end

  def test_auto_timestamp
    ts = A2A::Models::TaskStatus.new(state: "submitted")
    refute_nil ts.timestamp
    assert_match(/\d{4}-\d{2}-\d{2}/, ts.timestamp)
  end

  def test_explicit_timestamp_preserved
    ts = A2A::Models::TaskStatus.new(state: "submitted", timestamp: "2026-01-01T00:00:00Z")
    assert_equal "2026-01-01T00:00:00Z", ts.timestamp
  end

  def test_terminal_states
    assert A2A::Models::TaskStatus.new(state: "completed").terminal?
    assert A2A::Models::TaskStatus.new(state: "failed").terminal?
    assert A2A::Models::TaskStatus.new(state: "canceled").terminal?
    assert A2A::Models::TaskStatus.new(state: "rejected").terminal?
    refute A2A::Models::TaskStatus.new(state: "working").terminal?
  end

  def test_interrupted_states
    assert A2A::Models::TaskStatus.new(state: "input_required").interrupted?
    assert A2A::Models::TaskStatus.new(state: "auth_required").interrupted?
    refute A2A::Models::TaskStatus.new(state: "working").interrupted?
  end

  def test_active_states
    assert A2A::Models::TaskStatus.new(state: "submitted").active?
    assert A2A::Models::TaskStatus.new(state: "working").active?
    refute A2A::Models::TaskStatus.new(state: "completed").active?
  end

  def test_with_message
    msg = A2A::Models::Message.agent("error detail")
    ts = A2A::Models::TaskStatus.new(state: "failed", message: msg)
    assert_equal "error detail", ts.message.text_content
  end

  def test_from_hash
    h = { "state" => "working", "timestamp" => "2026-01-01T00:00:00Z" }
    ts = A2A::Models::TaskStatus.from_hash(h)
    assert_equal "working", ts.state
    assert_equal "2026-01-01T00:00:00Z", ts.timestamp
  end
end

class TestTask < Minitest::Test
  def submitted_task
    A2A::Models::Task.new(
      status: A2A::Models::TaskStatus.new(state: "submitted")
    )
  end

  def test_auto_uuid_for_id_and_context_id
    task = submitted_task
    refute_nil task.id
    refute_nil task.context_id
    assert_match(/\A[0-9a-f-]{36}\z/, task.id)
    assert_match(/\A[0-9a-f-]{36}\z/, task.context_id)
  end

  def test_explicit_ids_preserved
    task = A2A::Models::Task.new(
      id: "task-1",
      context_id: "ctx-1",
      status: A2A::Models::TaskStatus.new(state: "submitted")
    )
    assert_equal "task-1", task.id
    assert_equal "ctx-1", task.context_id
  end

  def test_state_delegates_to_status
    task = submitted_task
    assert_equal "submitted", task.state
  end

  def test_terminal_delegates
    task = submitted_task
    refute task.terminal?
    task.complete!
    assert task.terminal?
    assert_equal "completed", task.state
  end

  def test_interrupted_delegates
    task = submitted_task
    refute task.interrupted?
    task.require_input!
    assert task.interrupted?
    assert_equal "input_required", task.state
  end

  def test_start!
    task = submitted_task
    task.start!
    assert_equal "working", task.state
  end

  def test_complete_with_artifacts
    task = submitted_task
    art = A2A::Models::Artifact.new(parts: [A2A::Models::Part.text("done")])
    task.complete!(artifacts: [art])
    assert_equal "completed", task.state
    assert_equal 1, task.artifacts.length
  end

  def test_fail!
    task = submitted_task
    task.fail!(message: A2A::Models::Message.agent("oops"))
    assert_equal "failed", task.state
    assert_equal "oops", task.status.message.text_content
  end

  def test_cancel!
    task = submitted_task
    task.cancel!
    assert_equal "canceled", task.state
  end

  def test_reject!
    task = submitted_task
    task.reject!
    assert_equal "rejected", task.state
  end

  def test_require_input!
    task = submitted_task
    task.require_input!
    assert_equal "input_required", task.state
    assert task.interrupted?
  end

  def test_require_auth!
    task = submitted_task
    task.require_auth!
    assert_equal "auth_required", task.state
    assert task.interrupted?
  end

  def test_to_h_roundtrip
    task = A2A::Models::Task.new(
      id: "t-1",
      context_id: "c-1",
      status: A2A::Models::TaskStatus.new(state: "working", timestamp: "2026-01-01T00:00:00Z")
    )
    h = task.to_h
    task2 = A2A::Models::Task.from_hash(h)
    assert_equal "t-1", task2.id
    assert_equal "working", task2.state
  end
end
