# frozen_string_literal: true

require "test_helper"

class TestMessage < Minitest::Test
  def test_user_factory_with_string
    msg = A2A::Models::Message.user("hello")
    assert msg.user?
    refute msg.agent?
    assert_equal 1, msg.parts.length
    assert msg.parts.first.text?
    assert_equal "hello", msg.parts.first.text
    refute_nil msg.message_id
  end

  def test_agent_factory_with_string
    msg = A2A::Models::Message.agent("response")
    assert msg.agent?
    assert_equal "response", msg.text_content
  end

  def test_user_factory_with_part
    part = A2A::Models::Part.text("from part")
    msg = A2A::Models::Message.user(part)
    assert_equal part, msg.parts.first
  end

  def test_user_factory_multiple_content
    msg = A2A::Models::Message.user("first", "second")
    assert_equal 2, msg.parts.length
    assert_equal "first\nsecond", msg.text_content
  end

  def test_auto_uuid_on_initialize
    msg = A2A::Models::Message.new(role: "user", parts: [])
    refute_nil msg.message_id
    assert_match(/\A[0-9a-f-]{36}\z/, msg.message_id)
  end

  def test_valid_with_role_and_parts
    msg = A2A::Models::Message.user("hello")
    assert msg.valid?
  end

  def test_invalid_with_empty_parts
    msg = A2A::Models::Message.new(role: "user", parts: [])
    refute msg.valid?
  end

  def test_invalid_without_role
    msg = A2A::Models::Message.new(role: nil, parts: [A2A::Models::Part.text("hi")])
    refute msg.valid?
  end

  def test_text_content_joins_text_parts
    msg = A2A::Models::Message.user("a", "b")
    assert_equal "a\nb", msg.text_content
  end

  def test_to_h_roundtrip
    msg = A2A::Models::Message.user("hello")
    h = msg.to_h
    msg2 = A2A::Models::Message.from_hash(h)
    assert_equal "hello", msg2.text_content
    assert_equal A2A::Models::Types::Role::USER, msg2.role
  end

  def test_from_hash_with_camel_case
    h = {
      "messageId"   => "abc-123",
      "role"        => "user",
      "parts"       => [{ "text" => "hi", "mediaType" => "text/plain" }]
    }
    msg = A2A::Models::Message.from_hash(h)
    assert_equal "abc-123", msg.message_id
    assert_equal "user", msg.role
    assert_equal "hi", msg.text_content
  end
end
