#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/07_agent_chaining/client.rb
#
# Start the server first:
#   bundle exec ruby examples/07_agent_chaining/server.rb
#
# What this demo shows:
#   1. Three agents are discoverable via their individual agent cards.
#   2. The client calls only /pipeline — it has no knowledge of the other agents.
#   3. PipelineAgent internally calls /reverse then /shout via A2A.client,
#      demonstrating agent-to-agent chaining over the A2A protocol.
#   4. The result exposes all three stages so the chain is visible.
#   5. The sub-agents are also called directly to confirm they work standalone.

require_relative "../common_config"

BASE_URL     = "http://localhost:9292"
REVERSE_URL  = "#{BASE_URL}/reverse"
SHOUT_URL    = "#{BASE_URL}/shout"
PIPELINE_URL = "#{BASE_URL}/pipeline"

def divider = puts("─" * 60)

def artifact_text(task)
  task.artifacts&.first&.parts&.first&.text || "(no artifact)"
end

# ---------------------------------------------------------------------------
# Discover all three agents
# ---------------------------------------------------------------------------
puts
puts "=== Agent Discovery ==="
[
  ["ReverseAgent",  REVERSE_URL],
  ["ShoutAgent",    SHOUT_URL],
  ["PipelineAgent", PIPELINE_URL]
].each do |expected_name, url|
  card = A2A.client(url: url).agent_card
  puts "  #{url.ljust(32)} → #{card.name}: #{card.description}"
end
puts
divider

# ---------------------------------------------------------------------------
# Call the pipeline with several inputs — client speaks only to /pipeline
# ---------------------------------------------------------------------------
pipeline = A2A.client(url: PIPELINE_URL)

inputs = [
  "the quick brown fox jumps over the lazy dog",
  "agent to agent communication is the future",
  "simple is better than complex"
]

puts <<~HEREDOC

  === Pipeline calls (client speaks only to /pipeline) ===

HEREDOC

results = inputs.map do |text|
  task   = pipeline.send_task(message: A2A::Models::Message.user(text))
  output = artifact_text(task)
  puts <<~HEREDOC
    Input:  #{text}
    #{output.lines.map { |l| "  #{l}" }.join}
  HEREDOC
  { input: text, output: output, state: task.status.state }
end

divider

# ---------------------------------------------------------------------------
# Call sub-agents directly to show they work standalone
# ---------------------------------------------------------------------------
puts <<~HEREDOC

  === Sub-agents called directly (verification) ===

HEREDOC
sample = "hello world from A2A"

reverse_task = A2A.client(url: REVERSE_URL).send_task(
  message: A2A::Models::Message.user(sample)
)
shout_task = A2A.client(url: SHOUT_URL).send_task(
  message: A2A::Models::Message.user(sample)
)

puts <<~HEREDOC
  Input:                  #{sample}
  /reverse result:        #{artifact_text(reverse_task)}
  /shout   result:        #{artifact_text(shout_task)}

HEREDOC

divider

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
all_completed = results.all? { |r| r[:state] == "completed" }

pipeline_correct = results.all? do |r|
  words    = r[:input].split
  reversed = words.reverse.join(" ")
  shouted  = reversed.upcase
  r[:output].include?(shouted)
end

standalone_reverse_ok = artifact_text(reverse_task) == sample.split.reverse.join(" ")
standalone_shout_ok   = artifact_text(shout_task)   == sample.upcase
all_ok                = all_completed && pipeline_correct && standalone_reverse_ok && standalone_shout_ok

puts <<~HEREDOC

  === Verification ===
    All pipeline tasks completed       : #{all_completed          ? 'PASS' : 'FAIL'}
    Pipeline output matches chain      : #{pipeline_correct       ? 'PASS' : 'FAIL'}
    ReverseAgent standalone correct    : #{standalone_reverse_ok  ? 'PASS' : 'FAIL'}
    ShoutAgent standalone correct      : #{standalone_shout_ok    ? 'PASS' : 'FAIL'}

HEREDOC
puts(all_ok ? "All assertions passed." : "One or more assertions failed.")
