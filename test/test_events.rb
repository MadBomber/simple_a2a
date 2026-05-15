# frozen_string_literal: true

require "test_helper"

class TestTaskStatusUpdateEvent < Minitest::Test
  def make_status(state)
    A2A::Models::TaskStatus.new(state: state, timestamp: "2026-01-01T00:00:00Z")
  end


  def test_required_fields
    ev = A2A::Models::TaskStatusUpdateEvent.new(
      task_id: "t-1",
      context_id: "c-1",
      status: make_status("working")
    )
    assert ev.valid?
    assert_equal "t-1", ev.task_id
    assert_equal "c-1", ev.context_id
    assert_equal "working", ev.status.state
  end


  def test_final_defaults_false
    ev = A2A::Models::TaskStatusUpdateEvent.new(
      task_id: "t-1", context_id: "c-1", status: make_status("working")
    )
    refute ev.final?
  end


  def test_final_true
    ev = A2A::Models::TaskStatusUpdateEvent.new(
      task_id: "t-1", context_id: "c-1",
      status: make_status("completed"), final: true
    )
    assert ev.final?
  end


  def test_invalid_without_task_id
    ev = A2A::Models::TaskStatusUpdateEvent.new(
      task_id: nil, context_id: "c-1", status: make_status("working")
    )
    refute ev.valid?
  end


  def test_to_h_roundtrip
    ev = A2A::Models::TaskStatusUpdateEvent.new(
      task_id: "t-1", context_id: "c-1",
      status: make_status("completed"), final: true
    )
    h = ev.to_h
    assert_equal "t-1", h["taskId"]
    assert_equal true, h["final"]
    assert_equal "completed", h["status"]["state"]
  end


  def test_from_hash_coerces_status
    h = {
      "taskId" => "t-1",
      "contextId" => "c-1",
      "status" => { "state" => "failed", "timestamp" => "2026-01-01T00:00:00Z" },
      "final" => true
    }
    ev = A2A::Models::TaskStatusUpdateEvent.from_hash(h)
    assert_instance_of A2A::Models::TaskStatus, ev.status
    assert_equal "failed", ev.status.state
    assert ev.final?
  end
end


class TestTaskArtifactUpdateEvent < Minitest::Test
  def make_artifact
    A2A::Models::Artifact.new(
      artifact_id: "art-1",
      parts: [A2A::Models::Part.text("result")]
    )
  end


  def test_required_fields
    ev = A2A::Models::TaskArtifactUpdateEvent.new(
      task_id: "t-1", context_id: "c-1", artifact: make_artifact
    )
    assert ev.valid?
    assert_equal "art-1", ev.artifact.artifact_id
  end


  def test_append_defaults_false
    ev = A2A::Models::TaskArtifactUpdateEvent.new(
      task_id: "t-1", context_id: "c-1", artifact: make_artifact
    )
    refute ev.append?
    refute ev.last_chunk?
  end


  def test_append_and_last_chunk
    ev = A2A::Models::TaskArtifactUpdateEvent.new(
      task_id: "t-1", context_id: "c-1",
      artifact: make_artifact, append: true, last_chunk: true
    )
    assert ev.append?
    assert ev.last_chunk?
  end


  def test_invalid_without_artifact
    ev = A2A::Models::TaskArtifactUpdateEvent.new(
      task_id: "t-1", context_id: "c-1", artifact: nil
    )
    refute ev.valid?
  end


  def test_to_h_roundtrip
    ev = A2A::Models::TaskArtifactUpdateEvent.new(
      task_id: "t-1", context_id: "c-1",
      artifact: make_artifact, last_chunk: true
    )
    h = ev.to_h
    assert_equal "t-1", h["taskId"]
    assert_equal true, h["lastChunk"]
    assert_equal "art-1", h["artifact"]["artifactId"]
  end


  def test_from_hash_coerces_artifact
    h = {
      "taskId" => "t-1",
      "contextId" => "c-1",
      "artifact" => {
        "artifactId" => "art-2",
        "parts" => [{ "text" => "chunk", "mediaType" => "text/plain" }]
      },
      "append" => true
    }
    ev = A2A::Models::TaskArtifactUpdateEvent.from_hash(h)
    assert_instance_of A2A::Models::Artifact, ev.artifact
    assert_equal "art-2", ev.artifact.artifact_id
    assert ev.append?
  end
end
