# frozen_string_literal: true

require "test_helper"

class TestJsonRpcRequest < Minitest::Test
  def test_parse_valid_request
    json = JSON.generate({
                           "jsonrpc" => "2.0",
                           "id" => 1,
                           "method" => "tasks/send",
                           "params" => { "message" => {} }
                         })
    req = A2A::JsonRpc::Request.parse(json)
    assert_equal 1, req.id
    assert_equal "tasks/send", req.method
    assert_equal({ "message" => {} }, req.params)
  end


  def test_parse_notification_has_nil_id
    json = JSON.generate({ "jsonrpc" => "2.0", "method" => "tasks/send" })
    req = A2A::JsonRpc::Request.parse(json)
    assert_nil req.id
    assert req.notification?
  end


  def test_parse_raises_on_invalid_json
    assert_raises(A2A::JsonRpc::ParseError) do
      A2A::JsonRpc::Request.parse("{not valid json")
    end
  end


  def test_parse_raises_on_missing_jsonrpc_field
    json = JSON.generate({ "id" => 1, "method" => "foo" })
    assert_raises(A2A::JsonRpc::InvalidRequestError) do
      A2A::JsonRpc::Request.parse(json)
    end
  end


  def test_parse_raises_on_wrong_version
    json = JSON.generate({ "jsonrpc" => "1.0", "id" => 1, "method" => "foo" })
    assert_raises(A2A::JsonRpc::InvalidRequestError) do
      A2A::JsonRpc::Request.parse(json)
    end
  end


  def test_parse_raises_on_missing_method
    json = JSON.generate({ "jsonrpc" => "2.0", "id" => 1 })
    assert_raises(A2A::JsonRpc::InvalidRequestError) do
      A2A::JsonRpc::Request.parse(json)
    end
  end


  def test_parse_raises_on_non_hash
    assert_raises(A2A::JsonRpc::ParseError) do
      A2A::JsonRpc::Request.parse(JSON.generate([1, 2, 3]))
    end
  end
end


class TestJsonRpcResponse < Minitest::Test
  def test_success_response_structure
    json = A2A::JsonRpc::Response.success(id: 1, result: { "status" => "ok" })
    parsed = JSON.parse(json)
    assert_equal "2.0", parsed["jsonrpc"]
    assert_equal 1, parsed["id"]
    assert_equal({ "status" => "ok" }, parsed["result"])
    refute parsed.key?("error")
  end


  def test_error_response_structure
    json = A2A::JsonRpc::Response.error(id: 2, code: -32_601, message: "Method not found")
    parsed = JSON.parse(json)
    assert_equal "2.0", parsed["jsonrpc"]
    assert_equal 2, parsed["id"]
    assert_equal(-32_601, parsed["error"]["code"])
    assert_equal "Method not found", parsed["error"]["message"]
    refute parsed.key?("result")
  end


  def test_error_response_with_data
    json = A2A::JsonRpc::Response.error(id: 3, code: -32_602, message: "bad", data: { "field" => "x" })
    parsed = JSON.parse(json)
    assert_equal({ "field" => "x" }, parsed["error"]["data"])
  end


  def test_error_response_nil_id
    json = A2A::JsonRpc::Response.error(id: nil, code: -32_700, message: "parse error")
    parsed = JSON.parse(json)
    assert_nil parsed["id"]
  end


  def test_from_error_task_not_found
    json = A2A::JsonRpc::Response.from_error(id: 1, error: A2A::TaskNotFoundError.new("not found"))
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::TASK_NOT_FOUND, parsed["error"]["code"]
  end


  def test_from_error_version_not_supported
    json = A2A::JsonRpc::Response.from_error(id: 1, error: A2A::VersionNotSupportedError.new)
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::VERSION_NOT_SUPPORTED, parsed["error"]["code"]
  end


  def test_from_error_generic_maps_to_internal
    json = A2A::JsonRpc::Response.from_error(id: 1, error: RuntimeError.new("oops"))
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::INTERNAL_ERROR, parsed["error"]["code"]
    assert_equal "oops", parsed["error"]["message"]
  end


  def test_from_error_parse_error
    json = A2A::JsonRpc::Response.from_error(id: nil, error: A2A::JsonRpc::ParseError.new("bad json"))
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::PARSE_ERROR, parsed["error"]["code"]
  end


  def test_from_error_unsupported_operation
    json = A2A::JsonRpc::Response.from_error(id: 1,
                                             error: A2A::UnsupportedOperationError.new("not supported"))
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::UNSUPPORTED_OPERATION, parsed["error"]["code"]
    assert_equal "not supported", parsed["error"]["message"]
  end


  def test_from_error_content_type_not_supported
    err  = A2A::ContentTypeNotSupportedError.new("bad content type")
    json = A2A::JsonRpc::Response.from_error(id: 1, error: err)
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::CONTENT_TYPE_NOT_SUPPORTED, parsed["error"]["code"]
  end


  def test_from_error_invalid_agent_response
    json = A2A::JsonRpc::Response.from_error(id: 1,
                                             error: A2A::InvalidAgentResponseError.new("bad agent response"))
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_AGENT_RESPONSE, parsed["error"]["code"]
    assert_equal "bad agent response", parsed["error"]["message"]
  end


  def test_from_error_extension_required
    json = A2A::JsonRpc::Response.from_error(id: 1, error: A2A::ExtensionSupportRequiredError.new)
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::EXTENSION_REQUIRED, parsed["error"]["code"]
  end


  def test_from_error_invalid_request
    json = A2A::JsonRpc::Response.from_error(id: 1,
                                             error: A2A::JsonRpc::InvalidRequestError.new("bad request"))
    parsed = JSON.parse(json)
    assert_equal A2A::JsonRpc::ErrorCode::INVALID_REQUEST, parsed["error"]["code"]
    assert_equal "bad request", parsed["error"]["message"]
  end
end


class TestJsonRpcErrorCodes < Minitest::Test
  def test_all_standard_codes_defined
    assert_equal(-32_700, A2A::JsonRpc::ErrorCode::PARSE_ERROR)
    assert_equal(-32_600, A2A::JsonRpc::ErrorCode::INVALID_REQUEST)
    assert_equal(-32_601, A2A::JsonRpc::ErrorCode::METHOD_NOT_FOUND)
    assert_equal(-32_602, A2A::JsonRpc::ErrorCode::INVALID_PARAMS)
    assert_equal(-32_603, A2A::JsonRpc::ErrorCode::INTERNAL_ERROR)
  end


  def test_all_a2a_codes_defined
    assert_equal(-32_001, A2A::JsonRpc::ErrorCode::TASK_NOT_FOUND)
    assert_equal(-32_002, A2A::JsonRpc::ErrorCode::TASK_NOT_CANCELABLE)
    assert_equal(-32_003, A2A::JsonRpc::ErrorCode::PUSH_NOT_SUPPORTED)
    assert_equal(-32_004, A2A::JsonRpc::ErrorCode::UNSUPPORTED_OPERATION)
    assert_equal(-32_005, A2A::JsonRpc::ErrorCode::CONTENT_TYPE_NOT_SUPPORTED)
    assert_equal(-32_006, A2A::JsonRpc::ErrorCode::INVALID_AGENT_RESPONSE)
    assert_equal(-32_007, A2A::JsonRpc::ErrorCode::EXTENSION_REQUIRED)
    assert_equal(-32_008, A2A::JsonRpc::ErrorCode::VERSION_NOT_SUPPORTED)
  end
end
