#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/06_push_notifications/client.rb
#
# Start the server first:
#   bundle exec ruby examples/06_push_notifications/server.rb
#
# What this demo shows:
#   1. A local webhook receiver starts on port 9293 to capture push deliveries.
#   2. A task is submitted via tasks/sendSubscribe to get its ID immediately.
#   3. The client registers a webhook URL via tasks/pushNotification/set.
#   4. The server delivers an HTTP POST to the webhook after each step — no
#      open SSE connection required for the client to receive updates.
#   5. tasks/pushNotification/get and list confirm the config is stored.
#   6. tasks/pushNotification/delete removes the config; list confirms it gone.

require_relative "../common_config"
require "webrick"
require "json"

A2A_URL      = "http://localhost:9292"
WEBHOOK_PORT = 9293
WEBHOOK_URL  = "http://localhost:#{WEBHOOK_PORT}/webhook"

def divider = puts("─" * 60)

# ---------------------------------------------------------------------------
# Webhook receiver — a minimal WEBrick server that captures every incoming
# POST and forwards the parsed payload to a Queue for the main thread.
# ---------------------------------------------------------------------------
webhook_queue  = Queue.new
webhook_server = WEBrick::HTTPServer.new(
  Port:      WEBHOOK_PORT,
  Logger:    WEBrick::Log.new(File::NULL),
  AccessLog: []
)
webhook_server.mount_proc "/webhook" do |req, res|
  payload = JSON.parse(req.body) rescue { "raw" => req.body }
  webhook_queue << payload
  res.status = 200
  res.body   = "ok"
end
webhook_thread = Thread.new { webhook_server.start }
at_exit { webhook_server.shutdown }

puts <<~HEREDOC

  === Webhook receiver listening on #{WEBHOOK_URL} ===

HEREDOC

# ---------------------------------------------------------------------------
# Confirm the server is up and supports push notifications
# ---------------------------------------------------------------------------
base_client = A2A.client(url: A2A_URL)
card        = base_client.agent_card

puts <<~HEREDOC
  === Agent Card ===
    Name:               #{card.name}
    Description:        #{card.description}
    push_notifications: #{card.capabilities&.push_notifications}
    streaming:          #{card.capabilities&.streaming}

HEREDOC
abort "Agent does not advertise push notification support." unless card.capabilities&.push_notifications
divider

# ---------------------------------------------------------------------------
# Submit the task via sendSubscribe so it starts asynchronously.
# We only need the task ID from the first event; the SSE thread then drains
# silently in the background while we watch the webhook instead.
# ---------------------------------------------------------------------------
puts
puts "Submitting task via tasks/sendSubscribe…"

task_id     = nil
id_mutex    = Mutex.new
sse_thread  = Thread.new do
  A2A.sse_client(url: A2A_URL).send_subscribe(
    message: A2A::Models::Message.user("run push demo")
  ) do |event|
    case event
    when A2A::Models::TaskStatusUpdateEvent
      id_mutex.synchronize { task_id ||= event.task_id }
    end
  end
rescue => e
  puts "  SSE error: #{e.message}"
end

# Wait until we have the task ID (arrives with the first working event).
loop do
  sleep 0.05
  break if id_mutex.synchronize { task_id }
end

puts "  Task started: id=#{task_id[0, 8]}"
puts

# ---------------------------------------------------------------------------
# Register the webhook via tasks/pushNotification/set
# ---------------------------------------------------------------------------
puts "Registering webhook via tasks/pushNotification/set…"
base_client.send(:rpc_call, "tasks/pushNotification/set", {
  "id"                   => task_id,
  "pushNotificationConfig" => { "webhookUrl" => WEBHOOK_URL }
})
puts "  Webhook registered: #{WEBHOOK_URL}"
puts

# ---------------------------------------------------------------------------
# Confirm storage via tasks/pushNotification/get and list
# ---------------------------------------------------------------------------
get_result  = base_client.send(:rpc_call, "tasks/pushNotification/get",  { "id" => task_id })
list_result = base_client.send(:rpc_call, "tasks/pushNotification/list", {})

puts "tasks/pushNotification/get  → webhookUrl=#{get_result&.dig("pushNotificationConfig", "webhookUrl")}"
puts "tasks/pushNotification/list → #{list_result.length} config(s) registered"
divider

# ---------------------------------------------------------------------------
# Watch push deliveries arrive from the server.
# The server posts after each step; we print each payload as it lands.
# Stop when we see a final=true delivery.
# ---------------------------------------------------------------------------
puts <<~HEREDOC

  Watching webhook for incoming push notifications…
  (the client has NO open SSE connection — all updates arrive out-of-band)

HEREDOC

received = []
loop do
  payload = webhook_queue.pop
  received << payload

  status  = payload.dig("status", "state") || "unknown"
  message = payload.dig("status", "message")
  final   = payload["final"]

  line = "  push received → state=#{status}"
  line += " (#{message})" if message
  line += "  [FINAL]"     if final
  puts line

  break if final
end

puts
divider

# ---------------------------------------------------------------------------
# Delete the push config and confirm it is gone
# ---------------------------------------------------------------------------
puts
puts "Calling tasks/pushNotification/delete…"
base_client.send(:rpc_call, "tasks/pushNotification/delete", { "id" => task_id })

list_after = base_client.send(:rpc_call, "tasks/pushNotification/list", {})
puts "tasks/pushNotification/list → #{list_after.length} config(s) remaining"
puts

# Wait for the SSE thread to close naturally now that the task is complete.
sse_thread.join(5)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
divider
puts <<~HEREDOC

  === Summary ===
    Push notifications received : #{received.length}
    States delivered            : #{received.map { |p| p.dig("status", "state") }.join(" → ")}
    Final delivery seen         : #{received.any? { |p| p["final"] } ? 'yes' : 'no'}
    Config cleaned up           : #{list_after.empty? ? 'yes' : 'no'}

HEREDOC

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
states     = received.map { |p| p.dig("status", "state") }
last_state = states.last
push_ok    = received.length >= 2
final_ok   = received.last&.fetch("final", false)
state_ok   = last_state == "completed"
cleanup_ok = list_after.empty?
all_ok     = push_ok && final_ok && state_ok && cleanup_ok
puts <<~HEREDOC
  === Verification ===
    Push notifications received (≥2) : #{push_ok    ? 'PASS' : 'FAIL'}
    Final push delivery seen         : #{final_ok   ? 'PASS' : 'FAIL'}
    Final state is completed         : #{state_ok   ? 'PASS' : 'FAIL'}
    Config deleted successfully      : #{cleanup_ok ? 'PASS' : 'FAIL'}

HEREDOC
puts(all_ok ? "All assertions passed." : "One or more assertions failed.")
