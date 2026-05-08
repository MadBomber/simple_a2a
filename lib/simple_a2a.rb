# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require "uri"

require_relative "simple_a2a/version"
require_relative "simple_a2a/errors"

module SimpleA2a
  class << self
    attr_accessor :logger
  end
end
