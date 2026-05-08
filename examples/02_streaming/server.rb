#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/02_streaming/server.rb

require_relative "../common_config"

# ---------------------------------------------------------------------------
# Streaming executor — emits incremental events as it works.
# ---------------------------------------------------------------------------
class StreamingExecutor < A2A::Server::AgentExecutor
  WORDS = %w[The quick brown fox jumps over the lazy dog .].freeze

  def call(ctx)
    ctx.task.start!
    ctx.emit_status                   # TaskStatusUpdateEvent(state: "working")

    # Emit the response one word at a time to demonstrate artifact streaming
    WORDS.each_with_index do |word, i|
      text     = i.zero? ? word : " #{word}"
      artifact = A2A::Models::Artifact.new(
        index:      0,
        parts:      [A2A::Models::Part.text(text)],
        append:     i > 0,
        last_chunk: i == WORDS.length - 1
      )
      ctx.emit_artifact(artifact, append: i > 0, last_chunk: i == WORDS.length - 1)
    end

    ctx.task.complete!
    ctx.emit_status(final: true)      # TaskStatusUpdateEvent(state: "completed", final: true)
  end
end

# ---------------------------------------------------------------------------
# Agent card
# ---------------------------------------------------------------------------
card = A2A::Models::AgentCard.new(
  name:        "StreamingAgent",
  version:     "1.0",
  description: "Streams a sentence one word at a time",
  capabilities: A2A::Models::AgentCapabilities.new(streaming: true),
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "stream",
      description: "Returns a fixed sentence word-by-word via SSE"
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

puts "Starting StreamingAgent on http://localhost:9292"
puts "Press Ctrl-C to stop."
puts

A2A.server(agent_card: card, executor: StreamingExecutor.new).run
