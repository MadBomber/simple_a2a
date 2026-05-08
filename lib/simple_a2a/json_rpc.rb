# frozen_string_literal: true

module A2A
  module JsonRpc
    # A2A-defined JSON-RPC error codes
    module ErrorCode
      PARSE_ERROR             = -32700
      INVALID_REQUEST         = -32600
      METHOD_NOT_FOUND        = -32601
      INVALID_PARAMS          = -32602
      INTERNAL_ERROR          = -32603

      TASK_NOT_FOUND          = -32001
      TASK_NOT_CANCELABLE     = -32002
      PUSH_NOT_SUPPORTED      = -32003
      UNSUPPORTED_OPERATION   = -32004
      CONTENT_TYPE_NOT_SUPPORTED = -32005
      INVALID_AGENT_RESPONSE  = -32006
      EXTENSION_REQUIRED      = -32007
      VERSION_NOT_SUPPORTED   = -32008
    end

    class Request
      attr_reader :id, :method, :params

      def initialize(id:, method:, params: nil)
        @id     = id
        @method = method
        @params = params
      end

      def self.parse(json_string)
        data = JSON.parse(json_string)
        raise ParseError, "not a Hash" unless data.is_a?(Hash)
        raise InvalidRequestError, "missing jsonrpc field" unless data["jsonrpc"] == "2.0"
        raise InvalidRequestError, "missing method"       unless data.key?("method")

        new(
          id:     data["id"],
          method: data["method"],
          params: data["params"]
        )
      rescue JSON::ParserError => e
        raise ParseError, e.message
      end

      def notification? = id.nil?
    end

    class Response
      def self.success(id:, result:)
        JSON.generate({ "jsonrpc" => "2.0", "id" => id, "result" => result })
      end

      def self.error(id:, code:, message:, data: nil)
        err = { "code" => code, "message" => message }
        err["data"] = data if data
        JSON.generate({ "jsonrpc" => "2.0", "id" => id, "error" => err })
      end

      def self.from_error(id:, error:)
        code, msg = classify(error)
        error(id: id, code: code, message: msg)
      end

      def self.classify(error)
        case error
        when TaskNotFoundError          then [ErrorCode::TASK_NOT_FOUND,       error.message || "Task not found"]
        when TaskNotCancelableError     then [ErrorCode::TASK_NOT_CANCELABLE,   error.message || "Task not cancelable"]
        when PushNotificationNotSupportedError then [ErrorCode::PUSH_NOT_SUPPORTED, error.message || "Push notifications not supported"]
        when UnsupportedOperationError  then [ErrorCode::UNSUPPORTED_OPERATION, error.message || "Unsupported operation"]
        when ContentTypeNotSupportedError then [ErrorCode::CONTENT_TYPE_NOT_SUPPORTED, error.message || "Content type not supported"]
        when InvalidAgentResponseError  then [ErrorCode::INVALID_AGENT_RESPONSE, error.message || "Invalid agent response"]
        when ExtensionSupportRequiredError then [ErrorCode::EXTENSION_REQUIRED, error.message || "Extension required"]
        when VersionNotSupportedError   then [ErrorCode::VERSION_NOT_SUPPORTED, error.message || "Version not supported"]
        when ParseError                 then [ErrorCode::PARSE_ERROR,           error.message || "Parse error"]
        when InvalidRequestError        then [ErrorCode::INVALID_REQUEST,       error.message || "Invalid request"]
        when InvalidParamsError         then [ErrorCode::INVALID_PARAMS,        error.message || "Invalid params"]
        else                                 [ErrorCode::INTERNAL_ERROR,        error.message || "Internal error"]
        end
      end
    end

    # JSON-RPC specific errors (not A2A domain errors)
    class ParseError        < A2A::Error; end
    class InvalidRequestError < A2A::Error; end
    class InvalidParamsError  < A2A::Error; end
  end
end
