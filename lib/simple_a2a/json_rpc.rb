# frozen_string_literal: true

module A2A
  module JsonRpc
    # A2A-defined JSON-RPC error codes
    module ErrorCode
      PARSE_ERROR             = -32_700
      INVALID_REQUEST         = -32_600
      METHOD_NOT_FOUND        = -32_601
      INVALID_PARAMS          = -32_602
      INTERNAL_ERROR          = -32_603

      TASK_NOT_FOUND          = -32_001
      TASK_NOT_CANCELABLE     = -32_002
      PUSH_NOT_SUPPORTED      = -32_003
      UNSUPPORTED_OPERATION   = -32_004
      CONTENT_TYPE_NOT_SUPPORTED = -32_005
      INVALID_AGENT_RESPONSE  = -32_006
      EXTENSION_REQUIRED      = -32_007
      VERSION_NOT_SUPPORTED   = -32_008
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
          id: data["id"],
          method: data["method"],
          params: data["params"]
        )
      rescue JSON::ParserError => e
        raise ParseError, e.message
      end


      def notification? = id.nil?
    end


    # JSON-RPC specific errors (not A2A domain errors)
    class ParseError < A2A::Error; end
    class InvalidRequestError < A2A::Error; end
    class InvalidParamsError  < A2A::Error; end


    class Response
      ERROR_MAP = {
        A2A::TaskNotFoundError => [ErrorCode::TASK_NOT_FOUND,            "Task not found"],
        A2A::TaskNotCancelableError => [ErrorCode::TASK_NOT_CANCELABLE,
                                        "Task not cancelable"],
        A2A::PushNotificationNotSupportedError => [ErrorCode::PUSH_NOT_SUPPORTED,
                                                   "Push notifications not supported"],
        A2A::UnsupportedOperationError => [ErrorCode::UNSUPPORTED_OPERATION,
                                           "Unsupported operation"],
        A2A::ContentTypeNotSupportedError => [ErrorCode::CONTENT_TYPE_NOT_SUPPORTED,
                                              "Content type not supported"],
        A2A::InvalidAgentResponseError => [ErrorCode::INVALID_AGENT_RESPONSE,
                                           "Invalid agent response"],
        A2A::ExtensionSupportRequiredError => [ErrorCode::EXTENSION_REQUIRED,
                                               "Extension required"],
        A2A::VersionNotSupportedError => [ErrorCode::VERSION_NOT_SUPPORTED,
                                          "Version not supported"],
        ParseError => [ErrorCode::PARSE_ERROR,                "Parse error"],
        InvalidRequestError => [ErrorCode::INVALID_REQUEST,            "Invalid request"],
        InvalidParamsError => [ErrorCode::INVALID_PARAMS,             "Invalid params"]
      }.freeze


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
        entry = ERROR_MAP.find { |klass, _| error.is_a?(klass) }
        code, default_msg = entry ? entry.last : [ErrorCode::INTERNAL_ERROR, "Internal error"]
        [code, error.message || default_msg]
      end
    end
  end
end
