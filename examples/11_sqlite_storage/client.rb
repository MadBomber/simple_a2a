#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage:
#   bundle exec ruby examples/11_sqlite_storage/client.rb populate [ids_file]
#   bundle exec ruby examples/11_sqlite_storage/client.rb verify   [ids_file]
#
# populate — sends three tasks and writes their IDs to ids_file (default:
#            /tmp/a2a_sqlite_demo_ids.json) so the verify phase can find them.
#
# verify   — reads ids_file, retrieves each task from the (restarted) server,
#            and confirms all tasks are still present with state "completed".
#
# The run script in this directory manages both phases automatically.

require_relative "../common_config"
require "json"

URL      = "http://localhost:9292"
IDS_FILE = ARGV[1] || "/tmp/a2a_sqlite_demo_ids.json"
PHASE    = ARGV[0]

unless %w[populate verify].include?(PHASE)
  abort "Usage: client.rb <populate|verify> [ids_file]"
end

def divider = puts("─" * 60)

client = A2A.client(url: URL)

# ---------------------------------------------------------------------------
# Phase: populate
# ---------------------------------------------------------------------------
if PHASE == "populate"
  puts
  puts "=== Phase 1: Populate — sending tasks to SQLite-backed server ==="
  puts

  card = client.agent_card
  puts "  Agent : #{card.name}"
  puts "  DB    : shown in server output"
  puts

  messages = [
    "alpha — first message",
    "beta  — second message",
    "gamma — third message"
  ]

  ids = []
  messages.each do |text|
    task = client.send_task(message: A2A::Models::Message.user(text))
    ids << task.id
    puts "  sent  : #{text.strip}"
    puts "  id    : #{task.id}"
    puts "  state : #{task.status.state}"
    puts "  reply : #{task.artifacts.first&.parts&.first&.text}"
    puts
  end

  File.write(IDS_FILE, JSON.generate(ids))
  puts "  IDs written to #{IDS_FILE}"
  divider
  puts
  puts "Populate complete. The server will now be stopped and restarted."
  puts "The same database file will be passed to the new server instance."
  puts

# ---------------------------------------------------------------------------
# Phase: verify
# ---------------------------------------------------------------------------
else
  puts
  puts "=== Phase 2: Verify — confirming persistence after server restart ==="
  puts

  unless File.exist?(IDS_FILE)
    abort "IDs file not found: #{IDS_FILE} — run the populate phase first."
  end

  ids = JSON.parse(File.read(IDS_FILE))
  puts "  Reading #{ids.length} task IDs from #{IDS_FILE}"
  puts

  results = ids.map do |id|
    task = client.get_task(id)
    puts "  id    : #{id}"
    puts "  state : #{task.status.state}"
    puts "  reply : #{task.artifacts.first&.parts&.first&.text}"
    puts
    task
  rescue A2A::Error => e
    puts "  id    : #{id}  MISSING — #{e.message}"
    puts
    nil
  end

  divider

  all_present   = results.none?(&:nil?)
  all_completed = results.compact.all? { |t| t.status.state == "completed" }
  count_ok      = results.length == ids.length

  puts
  puts "=== Verification ==="
  puts "  All tasks present after restart : #{all_present   ? 'PASS' : 'FAIL'}"
  puts "  All tasks in completed state    : #{all_completed ? 'PASS' : 'FAIL'}"
  puts "  Task count matches (#{ids.length})         : #{count_ok     ? 'PASS' : 'FAIL'}"
  puts

  all_ok = all_present && all_completed && count_ok
  puts(all_ok ? "All assertions passed." : "One or more assertions failed.")
  exit(all_ok ? 0 : 1)
end
