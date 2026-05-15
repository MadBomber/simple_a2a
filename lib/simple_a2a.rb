# frozen_string_literal: true

require "zeitwerk"
require "json"
require "securerandom"
require "time"
require "uri"
require "base64"

module A2A
  class << self
    attr_accessor :logger

    def server(**)
      Server::Base.new(**)
    end


    def multi_server(**)
      Server::MultiAgent.new(**)
    end


    def broker_server(**)
      Server::BrokerServer.new(**)
    end


    def client(**)
      Client::Base.new(**)
    end


    def sse_client(**)
      Client::SSE.new(**)
    end
  end
end

# Require files that don't follow Zeitwerk naming conventions first
require_relative "simple_a2a/version"
require_relative "simple_a2a/errors"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "simple_a2a" => "A2A",
  "sse" => "SSE"
)
loader.ignore(
  "#{__dir__}/simple_a2a/version.rb",
  "#{__dir__}/simple_a2a/errors.rb",
  "#{__dir__}/simple_a2a/json_rpc.rb"
)
loader.setup

# json_rpc.rb depends on error classes; load after errors + loader setup
require_relative "simple_a2a/json_rpc"
