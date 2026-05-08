#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/01_basic_usage/server.rb

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "simple_a2a"

# ---------------------------------------------------------------------------
# Agent executor — contains all of your agent's logic.
# ---------------------------------------------------------------------------
class BasicExecutor < A2A::Server::AgentExecutor
  GREETINGS = %w[Hello Greetings Salutations Hey Howdy].freeze

  def call(ctx)
    input   = ctx.message.text_content.strip
    reply   = "#{GREETINGS.sample}: #{input}"

    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "reply",
        parts: [A2A::Models::Part.text(reply)]
      )
    ])
  end
end

# ---------------------------------------------------------------------------
# Agent card — describes this agent to any client that asks.
# ---------------------------------------------------------------------------
card = A2A::Models::AgentCard.new(
  name:        "BasicAgent",
  version:     "1.0",
  description: "A minimal A2A agent that greets every message it receives",
  capabilities: A2A::Models::AgentCapabilities.new,
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "greet",
      description: "Echoes the input with a random greeting"
    )
  ],
  interfaces: [
    A2A::Models::AgentInterface.new(
      type:    "json-rpc",
      url:     "http://localhost:9292",
      version: "1.0"
    )
  ]
)

# ---------------------------------------------------------------------------
# Start the server (blocks; Ctrl-C to stop).
# ---------------------------------------------------------------------------
puts "Starting BasicAgent on http://localhost:9292"
puts "Press Ctrl-C to stop."
puts

A2A.server(agent_card: card, executor: BasicExecutor.new).run
