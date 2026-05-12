# frozen_string_literal: true

require "simplecov"
require "simplecov-ai"

SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::AIFormatter
  ])
  # Only track files inside this project's lib/ — excludes all gem source files.
  add_filter { |src| src.filename !~ %r{/simple_a2a/lib/} }
  minimum_coverage 95
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "simple_a2a"
require "minitest/autorun"
require "minitest/reporters"

Minitest::Reporters.use! Minitest::Reporters::DefaultReporter.new(color: true)
