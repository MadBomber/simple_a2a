#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/05_cancellation/client.rb
#
# Start the server first:
#   bundle exec ruby examples/05_cancellation/server.rb
#
# What this demo shows:
#   1. Three tasks (A, B, C) are started via tasks/sendSubscribe so each
#      runs asynchronously inside Falcon's reactor.
#   2. After 3 seconds — while all tasks are still mid-flight — task B is
#      cancelled via tasks/cancel.
#   3. Task B's SSE stream receives a final canceled status event and closes.
#   4. Tasks A and C run to completion, unaffected.
#   5. Final states: A=completed, B=canceled, C=completed.

require_relative "../common_config"

URL        = "http://localhost:9292"
CANCEL_SEC = 3   # seconds before we cancel task B

def divider = puts("─" * 60)

def col(label, text)
  "[task #{label}] #{text}"
end

# ---------------------------------------------------------------------------
# Confirm the server is up and supports streaming
# ---------------------------------------------------------------------------
card = A2A.client(url: URL).agent_card

puts
puts "=== Agent Card ==="
puts "  Name:         #{card.name}"
puts "  Description:  #{card.description}"
puts "  Streaming:    #{card.capabilities&.streaming}"
puts
abort "Agent does not advertise streaming support." unless card.capabilities&.streaming
divider

# ---------------------------------------------------------------------------
# Start three streaming tasks in parallel threads.
# Each thread drives its own SSE loop and records every event it receives.
# A shared, mutex-protected hash lets the main thread see task IDs as soon
# as the first status event arrives from each task.
# ---------------------------------------------------------------------------
puts
puts "Starting tasks A, B, and C via tasks/sendSubscribe…"
puts "(each would take 10 s; task B will be cancelled after #{CANCEL_SEC}s)"
puts

task_ids  = {}
id_mutex  = Mutex.new
all_events = { "A" => [], "B" => [], "C" => [] }

threads = %w[A B C].map do |label|
  Thread.new do
    A2A.sse_client(url: URL).send_subscribe(
      message: A2A::Models::Message.user("task #{label}")
    ) do |event|
      case event
      when A2A::Models::TaskStatusUpdateEvent
        id_mutex.synchronize { task_ids[label] ||= event.task_id }
        all_events[label] << event
        state = event.status.state
        msg   = event.status.message ? " (#{event.status.message})" : ""
        puts col(label, "status=#{state}#{msg}")

      when A2A::Models::TaskArtifactUpdateEvent
        all_events[label] << event

      when Hash
        puts col(label, "error: #{event.dig('error', 'message')}")
      end
    end
  rescue => e
    puts col(label, "stream error: #{e.message}")
  end
end

# ---------------------------------------------------------------------------
# Wait until task B has checked in (first status event), then cancel it.
# ---------------------------------------------------------------------------
loop do
  sleep 0.1
  break if id_mutex.synchronize { task_ids["B"] }
end

puts
puts "Task B is running — waiting #{CANCEL_SEC}s then cancelling…"
sleep CANCEL_SEC

task_b_id = id_mutex.synchronize { task_ids["B"] }
puts
begin
  cancelled = A2A.client(url: URL).cancel_task(task_b_id)
  puts col("B", "cancel sent → state=#{cancelled.status.state}")
rescue A2A::Error => e
  puts col("B", "cancel failed: #{e.message}")
end
puts

# ---------------------------------------------------------------------------
# Wait for all three SSE streams to close.
# ---------------------------------------------------------------------------
threads.each(&:join)

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
divider
puts
puts "=== Final States ==="

%w[A B C].each do |label|
  events  = all_events[label]
  last_st = events.select { |e| e.is_a?(A2A::Models::TaskStatusUpdateEvent) }.last
  artifact = events.select { |e| e.is_a?(A2A::Models::TaskArtifactUpdateEvent) }
              .last&.artifact&.parts&.first&.text

  state = last_st&.status&.state || "unknown"
  line  = "state=#{state.ljust(10)}  events received=#{events.length}"
  line += "  result: #{artifact}"       if artifact
  line += "  ← cancelled mid-flight"   if state == "canceled"
  puts col(label, line)
end

puts

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
puts "=== Verification ==="

def final_state(events)
  events.select { |e| e.is_a?(A2A::Models::TaskStatusUpdateEvent) }
        .last&.status&.state
end

a_ok = final_state(all_events["A"]) == "completed"
b_ok = final_state(all_events["B"]) == "canceled"
c_ok = final_state(all_events["C"]) == "completed"

puts "  Task A completed normally : #{a_ok ? 'PASS' : 'FAIL'}"
puts "  Task B was cancelled      : #{b_ok ? 'PASS' : 'FAIL'}"
puts "  Task C completed normally : #{c_ok ? 'PASS' : 'FAIL'}"
puts
puts(a_ok && b_ok && c_ok ? "All assertions passed." : "One or more assertions failed.")
