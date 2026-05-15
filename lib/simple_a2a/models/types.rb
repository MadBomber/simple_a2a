# frozen_string_literal: true

module A2A
  module Models
    module Types
      module TaskState
        SUBMITTED      = "submitted"
        WORKING        = "working"
        COMPLETED      = "completed"
        FAILED         = "failed"
        CANCELED       = "canceled"
        REJECTED       = "rejected"
        INPUT_REQUIRED = "input_required"
        AUTH_REQUIRED  = "auth_required"

        TERMINAL    = [COMPLETED, FAILED, CANCELED, REJECTED].freeze
        INTERRUPTED = [INPUT_REQUIRED, AUTH_REQUIRED].freeze
        ACTIVE      = [SUBMITTED, WORKING].freeze
        ALL         = (TERMINAL + INTERRUPTED + ACTIVE).freeze

        def self.terminal?(state)    = TERMINAL.include?(state)
        def self.interrupted?(state) = INTERRUPTED.include?(state)
        def self.active?(state)      = ACTIVE.include?(state)
      end


      module Role
        USER  = "user"
        AGENT = "agent"
        ALL   = [USER, AGENT].freeze
      end


      module BindingType
        JSON_RPC = "json-rpc"
        HTTP     = "http"
        GRPC     = "grpc"
      end
    end
  end
end
