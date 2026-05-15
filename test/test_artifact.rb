# frozen_string_literal: true

require "test_helper"

class TestArtifact < Minitest::Test
  def test_auto_uuid
    art = A2A::Models::Artifact.new(parts: [A2A::Models::Part.text("x")])
    refute_nil art.artifact_id
    assert_match(/\A[0-9a-f-]{36}\z/, art.artifact_id)
  end


  def test_explicit_artifact_id_preserved
    art = A2A::Models::Artifact.new(artifact_id: "my-id", parts: [A2A::Models::Part.text("x")])
    assert_equal "my-id", art.artifact_id
  end


  def test_valid_with_parts
    art = A2A::Models::Artifact.new(parts: [A2A::Models::Part.text("result")])
    assert art.valid?
  end


  def test_invalid_with_empty_parts
    art = A2A::Models::Artifact.new(parts: [])
    refute art.valid?
  end


  def test_name_and_description
    art = A2A::Models::Artifact.new(
      name: "output.txt",
      description: "The result",
      parts: [A2A::Models::Part.text("content")]
    )
    assert_equal "output.txt", art.name
    assert_equal "The result", art.description
  end


  def test_to_h_roundtrip
    art = A2A::Models::Artifact.new(
      artifact_id: "art-1",
      name: "test",
      parts: [A2A::Models::Part.text("hello")]
    )
    h = art.to_h
    art2 = A2A::Models::Artifact.from_hash(h)
    assert_equal "art-1", art2.artifact_id
    assert_equal "test", art2.name
    assert_equal "hello", art2.parts.first.text
  end
end
