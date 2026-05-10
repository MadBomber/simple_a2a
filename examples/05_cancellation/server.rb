#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/05_cancellation/server.rb
#
# Hosts a single agent whose tasks take ~10 seconds to complete,
# giving the client time to cancel individual tasks while others
# keep running.

require_relative "../common_config"

# ---------------------------------------------------------------------------
# Executor — simulates a slow 10-step pipeline (1 s per step).
# Emits a status event after each step so the SSE stream shows progress.
# Checks ctx.task.terminal? between steps so a cancel takes effect promptly.
# ---------------------------------------------------------------------------
class SlowExecutor < A2A::Server::AgentExecutor
  STEPS    = 10
  STEP_SEC = 1.0

  def call(ctx)
    ctx.task.start!
    ctx.emit_status

    STEPS.times do |i|
      return if ctx.task.terminal?
      sleep STEP_SEC
      return if ctx.task.terminal?

      ctx.task.status = A2A::Models::TaskStatus.new(
        state:   A2A::Models::Types::TaskState::WORKING,
        message: "Step #{i + 1}/#{STEPS} complete"
      )
      ctx.emit_status
    end

    return if ctx.task.terminal?

    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "result",
        parts: [A2A::Models::Part.text("All #{STEPS} steps finished for task #{ctx.task.id[0, 8]}")]
      )
    ])
    ctx.emit_status(final: true)
  end
end

# ---------------------------------------------------------------------------
# Agent card
# ---------------------------------------------------------------------------
card = A2A::Models::AgentCard.new(
  name:         "SlowAgent",
  version:      "1.0",
  description:  "A slow 10-step agent — demonstrates mid-flight task cancellation",
  capabilities: A2A::Models::AgentCapabilities.new(streaming: true),
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "slow_task",
      description: "Runs 10 steps at 1 s each; can be cancelled at any point"
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

puts "Starting SlowAgent on http://localhost:9292"
puts "Each task takes #{SlowExecutor::STEPS * SlowExecutor::STEP_SEC}s to complete without cancellation."
puts "Press Ctrl-C to stop."
puts

A2A.server(agent_card: card, executor: SlowExecutor.new).run
