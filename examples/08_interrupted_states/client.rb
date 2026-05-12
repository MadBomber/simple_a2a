#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/08_interrupted_states/client.rb
#
# Start the server first:
#   bundle exec ruby examples/08_interrupted_states/server.rb
#
# What this demo shows:
#
#   Scenario A — input_required (OrderAgent):
#     Turn 1: client sends an initial request → agent pauses with input_required
#             and a question in status.message
#     Turn 2: client reads the question, sends the answer with the same
#             context_id → agent completes the task
#
#   Scenario B — auth_required (VaultAgent):
#     Turn 1: client requests protected data → agent pauses with auth_required
#     Turn 2: client sends the wrong token → agent stays in auth_required
#     Turn 3: client sends the correct token → agent completes the task
#
# Each turn is a separate tasks/send call. The agents use message.context_id
# to thread the conversation across calls.

require_relative "../common_config"

BASE_URL  = "http://localhost:9292"
ORDER_URL = "#{BASE_URL}/order"
VAULT_URL = "#{BASE_URL}/vault"

def divider = puts("─" * 60)

def msg(text, context_id:)
  A2A::Models::Message.new(
    role:       A2A::Models::Types::Role::USER,
    parts:      [A2A::Models::Part.text(text)],
    context_id: context_id
  )
end

def show_task(label, task)
  state   = task.status.state
  message = task.status.message
  artifact = task.artifacts&.first&.parts&.first&.text

  puts "  [#{label}] state=#{state}"
  puts "            agent says: #{message}"  if message
  puts "            result:     #{artifact}" if artifact
end

# ---------------------------------------------------------------------------
# Scenario A — input_required
# ---------------------------------------------------------------------------
puts <<~HEREDOC

  === Scenario A: input_required (OrderAgent) ===

HEREDOC

order = A2A.client(url: ORDER_URL)
conv_a = SecureRandom.uuid

puts "  context_id: #{conv_a[0, 8]}…"
puts

# Turn 1 — agent doesn't know what to make yet
task_a1 = order.send_task(message: msg("I'd like to place an order", context_id: conv_a))
show_task("turn 1", task_a1)

abort "Expected input_required, got #{task_a1.status.state}" unless task_a1.status.state == "input_required"

puts <<~HEREDOC

  Client reads the question and answers: 'pasta'

HEREDOC

# Turn 2 — client answers with the same context_id
task_a2 = order.send_task(message: msg("pasta", context_id: conv_a))
show_task("turn 2", task_a2)

divider

# ---------------------------------------------------------------------------
# Scenario B — auth_required (with a wrong token first)
# ---------------------------------------------------------------------------
puts <<~HEREDOC

  === Scenario B: auth_required (VaultAgent) ===

HEREDOC

vault  = A2A.client(url: VAULT_URL)
conv_b = SecureRandom.uuid

puts "  context_id: #{conv_b[0, 8]}…"
puts

# Turn 1 — agent demands a token
task_b1 = vault.send_task(message: msg("show me the secret data", context_id: conv_b))
show_task("turn 1", task_b1)

abort "Expected auth_required, got #{task_b1.status.state}" unless task_b1.status.state == "auth_required"

puts <<~HEREDOC

  Client sends the wrong token: 'wrong-token'

HEREDOC

# Turn 2 — wrong token; agent stays blocked
task_b2 = vault.send_task(message: msg("wrong-token", context_id: conv_b))
show_task("turn 2", task_b2)

abort "Expected auth_required, got #{task_b2.status.state}" unless task_b2.status.state == "auth_required"

puts <<~HEREDOC

  Client sends the correct token: 'open-sesame'

HEREDOC

# Turn 3 — correct token; agent unlocks
task_b3 = vault.send_task(message: msg("open-sesame", context_id: conv_b))
show_task("turn 3", task_b3)

divider

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
a_paused   = task_a1.status.state == "input_required"
a_asked    = task_a1.status.message&.include?("Options:")
a_complete = task_a2.status.state == "completed"
a_artifact = task_a2.artifacts&.first&.parts&.first&.text&.include?("pasta")

b_blocked1  = task_b1.status.state == "auth_required"
b_blocked2  = task_b2.status.state == "auth_required"
b_complete  = task_b3.status.state == "completed"
b_artifact  = task_b3.artifacts&.first&.parts&.first&.text&.include?("treasure")

all_ok = a_paused && a_asked && a_complete && a_artifact &&
         b_blocked1 && b_blocked2 && b_complete && b_artifact

puts <<~HEREDOC

  === Verification ===
    [order] turn 1 paused with input_required : #{a_paused   ? 'PASS' : 'FAIL'}
    [order] turn 1 included a question        : #{a_asked    ? 'PASS' : 'FAIL'}
    [order] turn 2 completed after answer     : #{a_complete ? 'PASS' : 'FAIL'}
    [order] turn 2 artifact mentions pasta    : #{a_artifact ? 'PASS' : 'FAIL'}

    [vault] turn 1 paused with auth_required  : #{b_blocked1 ? 'PASS' : 'FAIL'}
    [vault] turn 2 stayed blocked (bad token) : #{b_blocked2 ? 'PASS' : 'FAIL'}
    [vault] turn 3 completed after good token : #{b_complete ? 'PASS' : 'FAIL'}
    [vault] turn 3 artifact contains secret   : #{b_artifact ? 'PASS' : 'FAIL'}

HEREDOC
puts(all_ok ? "All assertions passed." : "One or more assertions failed.")
