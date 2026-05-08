#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/02_streaming/client.rb
#
# Start the server first:
#   bundle exec ruby examples/02_streaming/server.rb

require_relative "../common_config"

URL = "http://localhost:9292"

client = A2A.sse_client(url: URL)

# ---------------------------------------------------------------------------
# 1. Confirm the agent advertises streaming support
# ---------------------------------------------------------------------------
card = client.agent_card
puts "=== Agent Card ==="
puts "  Name:      #{card.name}"
puts "  Streaming: #{card.capabilities&.streaming}"
puts

# ---------------------------------------------------------------------------
# 2. Subscribe and print events as they arrive
# ---------------------------------------------------------------------------
puts "=== Streaming Task ==="
print "  "

event_count    = 0
artifact_text  = +""

client.send_subscribe(message: A2A::Models::Message.user("go")) do |event|
  event_count += 1

  case event
  when A2A::Models::TaskStatusUpdateEvent
    state = event.status.state
    if state == "working"
      # nothing to print — artifact chunks carry the content
    else
      # terminal status — print on a fresh line
      puts
      puts "  [status] #{state}#{event.final? ? " (final)" : ""}"
    end

  when A2A::Models::TaskArtifactUpdateEvent
    chunk = event.artifact.parts.map(&:text).join
    artifact_text << chunk
    print chunk
    $stdout.flush

  else
    puts "  [unknown] #{event.inspect}"
  end
end

puts
puts
puts "=== Summary ==="
puts "  Events received : #{event_count}"
puts "  Full text       : #{artifact_text.strip.inspect}"
