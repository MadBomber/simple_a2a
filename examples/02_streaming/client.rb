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
puts "  Name:        #{card.name}"
puts "  Description: #{card.description}"
puts "  Streaming:   #{card.capabilities&.streaming}"
puts "  Source:      https://lamplight.guide/blog/the-god-particle/"
puts

# ---------------------------------------------------------------------------
# 2. Subscribe and print words as they stream in
# ---------------------------------------------------------------------------
puts "=== Streaming Article ==="
puts

event_count   = 0
artifact_text = +""
word_count    = 0
start_time    = nil
interrupted   = false

begin
  client.send_subscribe(message: A2A::Models::Message.user("stream")) do |event|
    event_count += 1

    case event
    when A2A::Models::TaskStatusUpdateEvent
      start_time = Time.now if event.status.state == "working"

    when A2A::Models::TaskArtifactUpdateEvent
      chunk = event.artifact.parts.map(&:text).join
      artifact_text << chunk
      word_count += chunk.split.length
      print chunk
      $stdout.flush

    else
      puts "  [unknown] #{event.inspect}"
    end
  end
rescue Interrupt
  interrupted = true
  puts "\n\n(interrupted)"
end

elapsed = start_time ? (Time.now - start_time) : 0
wpm     = elapsed > 0 ? (word_count / (elapsed / 60.0)).round : 0

puts
puts "=== Summary ==="
puts "  Words received  : #{word_count}"
puts "  Events received : #{event_count}"
puts "  Elapsed         : #{elapsed.round(1)}s — #{wpm} WPM effective"
puts "  Status          : #{interrupted ? "interrupted" : "completed"}"
