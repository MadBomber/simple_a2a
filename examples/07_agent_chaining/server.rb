#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/07_agent_chaining/server.rb
#
# Three agents on one port via A2A.multi_server:
#
#   /reverse   — reverses the word order of the input text
#   /shout     — uppercases the input text
#   /pipeline  — calls /reverse then /shout and returns all three stages
#
# The client only ever speaks to /pipeline. The chaining between agents
# happens entirely inside PipelineExecutor using A2A.client — the same
# client interface any external caller would use.

require_relative "../common_config"

BASE_URL = "http://localhost:9292"

# ---------------------------------------------------------------------------
# ReverseExecutor — reverses the word order of the input.
# ---------------------------------------------------------------------------
class ReverseExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    input    = ctx.message.text_content.strip
    reversed = input.split.reverse.join(" ")
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "reversed",
        parts: [A2A::Models::Part.text(reversed)]
      )
    ])
  end
end

# ---------------------------------------------------------------------------
# ShoutExecutor — uppercases the input.
# ---------------------------------------------------------------------------
class ShoutExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    input  = ctx.message.text_content.strip
    shouted = input.upcase
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "shouted",
        parts: [A2A::Models::Part.text(shouted)]
      )
    ])
  end
end

# ---------------------------------------------------------------------------
# PipelineExecutor — orchestrates the other two agents via A2A.client,
# then composes a result showing every stage.
# ---------------------------------------------------------------------------
class PipelineExecutor < A2A::Server::AgentExecutor
  def initialize(base_url:)
    @reverse_client = A2A.client(url: "#{base_url}/reverse")
    @shout_client   = A2A.client(url: "#{base_url}/shout")
  end

  def call(ctx)
    input = ctx.message.text_content.strip

    # Stage 1: call the ReverseAgent
    reversed = @reverse_client
      .send_task(message: A2A::Models::Message.user(input))
      .artifacts.first&.parts&.first&.text || input

    # Stage 2: feed the reversed text to the ShoutAgent
    shouted = @shout_client
      .send_task(message: A2A::Models::Message.user(reversed))
      .artifacts.first&.parts&.first&.text || reversed

    result = <<~RESULT.strip
      Input:    #{input}
      Reversed: #{reversed}
      Shouted:  #{shouted}
    RESULT

    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "pipeline_result",
        parts: [A2A::Models::Part.text(result)]
      )
    ])
  end
end

# ---------------------------------------------------------------------------
# Agent cards
# ---------------------------------------------------------------------------
def make_card(name:, description:, skill:, path:)
  A2A::Models::AgentCard.new(
    name:         name,
    version:      "1.0",
    description:  description,
    capabilities: A2A::Models::AgentCapabilities.new,
    skills: [
      A2A::Models::AgentSkill.new(name: skill, description: description)
    ],
    interfaces: [
      A2A::Models::AgentInterface.new(
        type:    "json-rpc",
        url:     "#{BASE_URL}#{path}",
        version: "1.0"
      )
    ]
  )
end

reverse_card  = make_card(
  name:        "ReverseAgent",
  description: "Reverses the word order of input text",
  skill:       "reverse",
  path:        "/reverse"
)

shout_card = make_card(
  name:        "ShoutAgent",
  description: "Uppercases input text",
  skill:       "shout",
  path:        "/shout"
)

pipeline_card = make_card(
  name:        "PipelineAgent",
  description: "Chains ReverseAgent then ShoutAgent and returns all three stages",
  skill:       "pipeline",
  path:        "/pipeline"
)

# ---------------------------------------------------------------------------
# Start the multi-agent server
# ---------------------------------------------------------------------------
puts <<~HEREDOC
  Starting multi-agent server on #{BASE_URL}
    /reverse   → ReverseAgent
    /shout     → ShoutAgent
    /pipeline  → PipelineAgent (chains the other two)
  Press Ctrl-C to stop.

HEREDOC

A2A.multi_server(
  agents: {
    "/reverse"  => { agent_card: reverse_card,  executor: ReverseExecutor.new },
    "/shout"    => { agent_card: shout_card,     executor: ShoutExecutor.new },
    "/pipeline" => { agent_card: pipeline_card,  executor: PipelineExecutor.new(base_url: BASE_URL) }
  },
  port: 9292
).run
