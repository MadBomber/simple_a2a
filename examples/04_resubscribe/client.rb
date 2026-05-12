#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/04_resubscribe/client.rb
#
# Start the server first:
#   bundle exec ruby examples/04_resubscribe/server.rb
#
# What this demo shows:
#   1. Subscriber 1 starts a streaming task via tasks/sendSubscribe.
#   2. Once the task ID is known, Subscriber 2 attaches via tasks/resubscribe.
#   3. Subscriber 2's first event is the current Task snapshot — not an
#      artifact or status update — proving it joined an in-flight stream.
#   4. Both subscribers then receive the remaining events independently.
#   5. The task completes once; both streams close cleanly.

require_relative "../common_config"
require "async"

URL   = "http://localhost:9292"
WIDTH = 42  # column width for side-by-side output

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def col(label, text, width = WIDTH)
  prefix = "[#{label}]"
  "#{prefix.ljust(14)} #{text.to_s.ljust(width)}"
end

def divider = puts("─" * (WIDTH * 2 + 16))

def print_header
  puts
  puts col("subscriber-1", "tasks/sendSubscribe (new task)") +
       col("subscriber-2", "tasks/resubscribe   (join mid-stream)")
  divider
end

# ---------------------------------------------------------------------------
# Agent card — confirm streaming capability
# ---------------------------------------------------------------------------
base = A2A.client(url: URL)
card = base.agent_card

puts <<~HEREDOC
  === Agent Card ===
    Name:        #{card.name}
    Description: #{card.description}
    Streaming:   #{card.capabilities&.streaming}

HEREDOC

abort "Agent does not advertise streaming support." unless card.capabilities&.streaming

# ---------------------------------------------------------------------------
# Run both subscribers concurrently inside a single Async reactor.
# ---------------------------------------------------------------------------
print_header

sub1_events = []
sub2_events = []
captured_task_id = nil

Async do |reactor|
  client1 = A2A.sse_client(url: URL)
  client2 = A2A.sse_client(url: URL)

  # Subscriber 1 — starts the task and streams from the beginning.
  sub1_task = reactor.async do
    client1.send_subscribe(message: A2A::Models::Message.user("analyze")) do |event|
      sub1_events << event

      case event
      when A2A::Models::TaskStatusUpdateEvent
        captured_task_id ||= event.task_id
        label = event.final? ? "status (final): #{event.status.state}" : "status: #{event.status.state}"
        puts col("subscriber-1", label)

      when A2A::Models::TaskArtifactUpdateEvent
        puts col("subscriber-1", event.artifact.parts.map(&:text).join)

      when Hash
        puts col("subscriber-1", "(error) #{event.dig('error', 'message')}")
      end
    end
  end

  # Wait until Subscriber 1 has seen the first event and given us the task ID.
  loop do
    break if captured_task_id
    reactor.sleep(0.05)
  end

  puts col("subscriber-2", "(resubscribing to task #{captured_task_id[0, 8]}…)")

  # Subscriber 2 — joins the running task.
  # First event is the Task snapshot; remaining events are the live stream.
  client2.resubscribe(task_id: captured_task_id) do |event|
    sub2_events << event

    case event
    when Hash
      # Task snapshot — the current state at the moment we subscribed.
      state = event.dig("status", "state") || "unknown"
      puts col("subscriber-2", "(snapshot) state=#{state}, steps so far: #{event['artifacts']&.length || 0}")

    when A2A::Models::TaskStatusUpdateEvent
      label = event.final? ? "status (final): #{event.status.state}" : "status: #{event.status.state}"
      puts col("subscriber-2", label)

    when A2A::Models::TaskArtifactUpdateEvent
      puts col("subscriber-2", event.artifact.parts.map(&:text).join)
    end
  end

  sub1_task.wait
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
snapshot       = sub2_events.find { |e| e.is_a?(Hash) && e.key?("status") }
sub2_artifacts = sub2_events.select { |e| e.is_a?(A2A::Models::TaskArtifactUpdateEvent) }
sub1_artifacts = sub1_events.select { |e| e.is_a?(A2A::Models::TaskArtifactUpdateEvent) }
divider
puts <<~HEREDOC

  === Summary ===
    Subscriber 1 — events received : #{sub1_events.length}
    Subscriber 1 — artifact steps  : #{sub1_artifacts.length}

    Subscriber 2 — events received : #{sub2_events.length}
    Subscriber 2 — task snapshot   : #{snapshot ? 'yes' : 'no (unexpected)'}
    Subscriber 2 — artifact steps  : #{sub2_artifacts.length}
    Subscriber 2 — joined at step  : #{sub1_artifacts.length - sub2_artifacts.length + 1} of 5

    Both streams terminated cleanly: #{
      sub1_events.any? { |e| e.is_a?(A2A::Models::TaskStatusUpdateEvent) && e.final? } &&
      sub2_events.any? { |e| e.is_a?(A2A::Models::TaskStatusUpdateEvent) && e.final? }
    }
HEREDOC
