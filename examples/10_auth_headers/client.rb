#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/10_auth_headers/client.rb
#
# Start the server first:
#   bundle exec ruby examples/10_auth_headers/server.rb
#
# What this demo shows:
#   1. Agent card discovery (GET) works for both clients — it is public.
#   2. An unauthenticated client (no headers) is rejected on send_task.
#   3. An authenticated client (headers: { "Authorization" => "Bearer ..." })
#      succeeds on send_task.
#   4. The headers: option accepts any key/value pairs, making it suitable
#      for Bearer tokens, API keys, or any custom header scheme.

require_relative "../common_config"

URL   = "http://localhost:9292"
TOKEN = "super-secret-token"

def divider = puts("─" * 60)

# ---------------------------------------------------------------------------
# Two clients — same URL, different headers
# ---------------------------------------------------------------------------
unauth_client = A2A.client(url: URL)
auth_client   = A2A.client(url: URL, headers: { "Authorization" => "Bearer #{TOKEN}" })

# ---------------------------------------------------------------------------
# Agent card — public endpoint, both clients can discover it
# ---------------------------------------------------------------------------
puts
card = unauth_client.agent_card
puts <<~HEREDOC
  === Agent Card (public — no auth required) ===
    Name:        #{card.name}
    Description: #{card.description}

HEREDOC
divider

# ---------------------------------------------------------------------------
# Unauthenticated client — rejected on RPC call
# ---------------------------------------------------------------------------
puts <<~HEREDOC

  === Unauthenticated client — no Authorization header ===

HEREDOC

unauth_error = nil
begin
  unauth_client.send_task(message: A2A::Models::Message.user("hello"))
  puts "  (unexpected success)"
rescue A2A::Error => e
  unauth_error = e
  puts "  Rejected as expected: #{e.message}"
end

divider

# ---------------------------------------------------------------------------
# Authenticated client — accepted
# ---------------------------------------------------------------------------
puts <<~HEREDOC

  === Authenticated client — Authorization: Bearer #{TOKEN} ===

HEREDOC

auth_task   = auth_client.send_task(message: A2A::Models::Message.user("hello from authorized client"))
auth_result = auth_task.artifacts&.first&.parts&.first&.text

puts "  state:  #{auth_task.status.state}"
puts "  result: #{auth_result}"

divider

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
card_ok      = card.name == "SecureAgent"
rejected_ok  = unauth_error&.message&.include?("Unauthorized")
accepted_ok  = auth_task.status.state == "completed"
result_ok    = auth_result&.include?("[authorized]")
all_ok       = card_ok && rejected_ok && accepted_ok && result_ok

puts <<~HEREDOC

  === Verification ===
    Agent card discoverable without auth : #{card_ok     ? 'PASS' : 'FAIL'}
    Unauthenticated call rejected        : #{rejected_ok ? 'PASS' : 'FAIL'}
    Authenticated call accepted          : #{accepted_ok ? 'PASS' : 'FAIL'}
    Authenticated result is correct      : #{result_ok   ? 'PASS' : 'FAIL'}

HEREDOC
puts(all_ok ? "All assertions passed." : "One or more assertions failed.")
