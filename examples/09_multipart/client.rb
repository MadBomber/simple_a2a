#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/09_multipart/client.rb [topic]
#
# Start the server first:
#   bundle exec ruby examples/09_multipart/server.rb
#
# What this demo shows:
#   A single artifact can carry multiple parts of different types.
#   The client inspects each part using the predicate methods (text?,
#   json?, raw?, url?) and processes each one appropriately:
#
#     Part.text     → print the prose
#     Part.json     → pretty-print the hash
#     Part.binary   → decode from base64, display as text or byte count
#     Part.from_url → display the URL reference

require_relative "../common_config"
require "json"

URL   = "http://localhost:9292"
topic = ARGV.first || "agent to agent protocol design"

def divider = puts("─" * 60)
def header(title) = puts("\n  ── #{title} ──\n")

# ---------------------------------------------------------------------------
# Discover the agent
# ---------------------------------------------------------------------------
client = A2A.client(url: URL)
card   = client.agent_card

puts <<~HEREDOC

  === Agent Card ===
    Name:        #{card.name}
    Description: #{card.description}

HEREDOC

# ---------------------------------------------------------------------------
# Send the task
# ---------------------------------------------------------------------------
puts "=== Sending task: #{topic.inspect} ==="
puts

task = client.send_task(message: A2A::Models::Message.user(topic))

puts "  state:     #{task.status.state}"
puts "  artifacts: #{task.artifacts.length}"

artifact = task.artifacts.first
puts "  artifact:  #{artifact.name} (#{artifact.parts.length} parts)"
divider

# ---------------------------------------------------------------------------
# Inspect each part by type
# ---------------------------------------------------------------------------
puts
puts "=== Parts ==="

artifact.parts.each_with_index do |part, i|
  puts
  puts "  Part #{i + 1} of #{artifact.parts.length}"

  if part.text?
    header "text  (media_type: #{part.media_type})"
    part.text.each_line { |l| puts "    #{l}" }

  elsif part.json?
    header "json  (filename: #{part.filename})"
    JSON.pretty_generate(part.data).each_line { |l| puts "    #{l}" }

  elsif part.raw?
    header "binary  (media_type: #{part.media_type}, filename: #{part.filename})"
    bytes = part.decoded_bytes
    puts <<~HEREDOC
      base64 length : #{part.raw.length} chars
      decoded bytes : #{bytes.bytesize}
      content:
    HEREDOC
    bytes.force_encoding("UTF-8").each_line { |l| puts "      #{l}" }

  elsif part.url?
    header "url  (media_type: #{part.media_type}, filename: #{part.filename})"
    puts "    #{part.url}"
  end
end

divider

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
parts = artifact.parts

text_part   = parts.find(&:text?)
json_part   = parts.find(&:json?)
binary_part = parts.find(&:raw?)
url_part    = parts.find(&:url?)

puts <<~HEREDOC

  === Verification ===
    text   part present and non-empty : #{(text_part   && !text_part.text.empty?)           ? 'PASS' : 'FAIL'}
    json   part present with hash     : #{(json_part   && json_part.data.is_a?(Hash))        ? 'PASS' : 'FAIL'}
    binary part decodes correctly     : #{(binary_part && binary_part.decoded_bytes.bytesize > 0) ? 'PASS' : 'FAIL'}
    url    part is a valid URL        : #{(url_part    && url_part.url.start_with?("https://")) ? 'PASS' : 'FAIL'}
    json   part topic matches input   : #{(json_part   && json_part.data["topic"] == topic)  ? 'PASS' : 'FAIL'}
    binary part is valid CSV          : #{(binary_part && binary_part.decoded_bytes.include?("rank")) ? 'PASS' : 'FAIL'}

HEREDOC

all_ok = text_part && json_part && binary_part && url_part &&
         !text_part.text.empty? &&
         json_part.data.is_a?(Hash) &&
         binary_part.decoded_bytes.bytesize > 0 &&
         url_part.url.start_with?("https://") &&
         json_part.data["topic"] == topic &&
         binary_part.decoded_bytes.include?("rank")

puts(all_ok ? "All assertions passed." : "One or more assertions failed.")
