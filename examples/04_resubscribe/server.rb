#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/04_resubscribe/server.rb
#
# Demonstrates tasks/resubscribe — multiple concurrent SSE subscribers
# watching the same running task.

require_relative "../common_config"

# ---------------------------------------------------------------------------
# Executor — simulates a multi-step analysis pipeline with visible pauses
# so a second subscriber has time to attach mid-stream.
# ---------------------------------------------------------------------------
class AnalysisExecutor < A2A::Server::AgentExecutor
  STEPS = [
    "Collecting data from sources",
    "Filtering and normalising records",
    "Running statistical analysis",
    "Detecting anomalies",
    "Generating final report"
  ].freeze

  STEP_DELAY = 1.2  # seconds between steps — wide enough for client to resubscribe

  def call(ctx)
    ctx.task.start!
    ctx.emit_status

    STEPS.each_with_index do |description, i|
      sleep STEP_DELAY

      artifact = A2A::Models::Artifact.new(
        index:      i,
        parts:      [A2A::Models::Part.text("Step #{i + 1}/#{STEPS.length}: #{description}")],
        last_chunk: true
      )
      ctx.emit_artifact(artifact, last_chunk: true)
    end

    ctx.task.complete!
    ctx.emit_status(final: true)
  end
end

# ---------------------------------------------------------------------------
# Agent card
# ---------------------------------------------------------------------------
card = A2A::Models::AgentCard.new(
  name:         "AnalysisAgent",
  version:      "1.0",
  description:  "Multi-step analysis pipeline — demonstrates tasks/resubscribe",
  capabilities: A2A::Models::AgentCapabilities.new(streaming: true),
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "analyze",
      description: "Runs a five-step analysis and streams each step as it completes"
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

total = AnalysisExecutor::STEPS.length * AnalysisExecutor::STEP_DELAY
puts <<~HEREDOC
  Starting AnalysisAgent on http://localhost:9292
  Task runs #{AnalysisExecutor::STEPS.length} steps × #{AnalysisExecutor::STEP_DELAY}s = ~#{total.round(0).to_i}s per run
  Press Ctrl-C to stop.

HEREDOC

A2A.server(agent_card: card, executor: AnalysisExecutor.new).run
