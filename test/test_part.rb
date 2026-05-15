# frozen_string_literal: true

require "test_helper"
require "base64"

class TestPart < Minitest::Test
  def test_text_factory
    part = A2A::Models::Part.text("hello")
    assert part.text?
    assert_equal "hello", part.text
    assert_equal "text/plain", part.media_type
    refute part.json?
    refute part.url?
    refute part.raw?
  end


  def test_text_factory_custom_media_type
    part = A2A::Models::Part.text("data", media_type: "text/csv", filename: "data.csv")
    assert_equal "text/csv", part.media_type
    assert_equal "data.csv", part.filename
  end


  def test_json_factory
    hash = { key: "value" }
    part = A2A::Models::Part.json(hash)
    assert part.json?
    assert_equal hash, part.data
    assert_equal "application/json", part.media_type
  end


  def test_url_factory
    part = A2A::Models::Part.from_url("https://example.com/file.png", media_type: "image/png")
    assert part.url?
    assert_equal "https://example.com/file.png", part.url
    assert_equal "image/png", part.media_type
  end


  def test_binary_factory
    bytes = "binary data"
    part = A2A::Models::Part.binary(bytes, media_type: "application/octet-stream")
    assert part.raw?
    assert_equal Base64.strict_encode64(bytes), part.raw
    assert_equal bytes, part.decoded_bytes
  end


  def test_valid_with_one_field
    assert A2A::Models::Part.text("hi").valid?
    assert A2A::Models::Part.json({}).valid?
    assert A2A::Models::Part.from_url("http://x.com", media_type: "image/png").valid?
  end


  def test_invalid_with_no_fields
    part = A2A::Models::Part.new
    refute part.valid?
  end


  def test_to_h_omits_nil_fields
    part = A2A::Models::Part.text("hi")
    h = part.to_h
    assert_equal "hi", h["text"]
    refute h.key?("raw")
    refute h.key?("url")
    refute h.key?("data")
  end


  def test_from_hash_roundtrip
    part = A2A::Models::Part.text("hello world")
    h = part.to_h
    part2 = A2A::Models::Part.from_hash(h)
    assert_equal "hello world", part2.text
    assert_equal "text/plain", part2.media_type
  end


  def test_from_hash_camel_case_keys
    part = A2A::Models::Part.from_hash({ "text" => "hi", "mediaType" => "text/plain" })
    assert_equal "hi", part.text
    assert_equal "text/plain", part.media_type
  end
end
