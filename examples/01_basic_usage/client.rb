#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/01_basic_usage/client.rb
#
# Start the server first:
#   bundle exec ruby examples/01_basic_usage/server.rb

require_relative "../common_config"

URL = "http://localhost:9292"

client = A2A.client(url: URL)

# ---------------------------------------------------------------------------
# 1. Discover the agent
# ---------------------------------------------------------------------------
card = client.agent_card
puts <<~HEREDOC
  === Agent Card ===
    Name:        #{card.name}
    Version:     #{card.version}
    Description: #{card.description}
    Skills:      #{card.skills.map(&:name).join(', ')}

HEREDOC

# ---------------------------------------------------------------------------
# 2. Send a few tasks
# ---------------------------------------------------------------------------
messages = [
  "world",
  "Ruby developers",
  "A2A protocol"
]

puts "=== Sending Tasks ==="
task_ids = messages.map do |text|
  task = client.send_task(message: A2A::Models::Message.user(text))

  reply = task.artifacts.first&.parts&.first&.text || "(no reply)"
  puts "  [#{task.status.state}] sent: #{text.inspect}"
  puts "           got: #{reply.inspect}"
  task.id
end
puts

# ---------------------------------------------------------------------------
# 3. List all tasks
# ---------------------------------------------------------------------------
puts "=== Task List ==="
all_tasks = client.list_tasks
all_tasks.each do |t|
  puts "  #{t.id}  state=#{t.status.state}"
end
puts "  Total: #{all_tasks.size}"
puts

# ---------------------------------------------------------------------------
# 4. Retrieve a single task by ID
# ---------------------------------------------------------------------------
retrieved = client.get_task(task_ids.first)
puts <<~HEREDOC
  === Retrieve Task ===
    id:    #{retrieved.id}
    state: #{retrieved.status.state}
    reply: #{retrieved.artifacts.first&.parts&.first&.text.inspect}

HEREDOC

# ---------------------------------------------------------------------------
# 5. Cancel a non-existent task (demonstrates error handling)
# ---------------------------------------------------------------------------
puts "=== Error Handling ==="
begin
  client.get_task("no-such-task-id")
rescue A2A::Error => e
  puts "  Caught expected error: #{e.message}"
end
