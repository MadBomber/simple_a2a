#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: BUNDLE_GEMFILE=examples/11_sqlite_storage/Gemfile \
#          bundle exec ruby examples/11_sqlite_storage/server.rb [db_path]
#
# The run script in this directory manages the full lifecycle automatically.
#
# Demonstrates injecting a custom Storage::Base implementation (SQLite3) into
# the simple_a2a server. The db_path argument lets two consecutive server
# instances share the same database file, proving that tasks created in the
# first run survive a full process restart.

require "sqlite3"
require_relative "../common_config"
require "json"
require "time"

# ---------------------------------------------------------------------------
# SqliteStorage — A2A::Storage::Base backed by SQLite3
# ---------------------------------------------------------------------------
class SqliteStorage < A2A::Storage::Base
  def initialize(path)
    @db    = SQLite3::Database.new(path)
    @mutex = Mutex.new
    @db.execute("PRAGMA journal_mode=WAL")
    @db.execute("PRAGMA busy_timeout=5000")
    setup_schema
  end

  def save(task)
    @mutex.synchronize do
      now = Time.now.iso8601
      @db.execute(
        "INSERT INTO tasks (id, data, created_at, updated_at) VALUES (?, ?, ?, ?) " \
        "ON CONFLICT(id) DO UPDATE SET data=excluded.data, updated_at=excluded.updated_at",
        [task.id, task.to_h.to_json, now, now]
      )
    end
    task
  end

  def find(id)
    row = @mutex.synchronize { @db.get_first_row("SELECT data FROM tasks WHERE id=?", [id]) }
    return nil unless row
    A2A::Models::Task.from_hash(JSON.parse(row[0]))
  end

  def find!(id)
    find(id) or raise A2A::TaskNotFoundError, "Task #{id} not found"
  end

  def delete(id)
    @mutex.synchronize { @db.execute("DELETE FROM tasks WHERE id=?", [id]) }
  end

  def list
    rows = @mutex.synchronize { @db.execute("SELECT data FROM tasks ORDER BY rowid") }
    rows.map { |row| A2A::Models::Task.from_hash(JSON.parse(row[0])) }
  end

  def size
    @mutex.synchronize { @db.get_first_value("SELECT COUNT(*) FROM tasks") }
  end

  def clear
    @mutex.synchronize { @db.execute("DELETE FROM tasks") }
  end

  private

  def setup_schema
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS tasks (
        id         TEXT PRIMARY KEY,
        data       TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
  end
end

# ---------------------------------------------------------------------------
# Executor — simple echo with a completion timestamp
# ---------------------------------------------------------------------------
class EchoExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    input = ctx.message.text_content.strip
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "reply",
        parts: [A2A::Models::Part.text("echo: #{input} (completed at #{Time.now.utc.iso8601})")]
      )
    ])
  end
end

# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
db_path = ARGV.first || File.join(__dir__, "tasks.db")
storage  = SqliteStorage.new(db_path)

card = A2A::Models::AgentCard.new(
  name:         "PersistentEchoAgent",
  version:      "1.0",
  description:  "Stores tasks in SQLite3; survives server restarts",
  capabilities: A2A::Models::AgentCapabilities.new,
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "echo",
      description: "Echoes any text back with a completion timestamp"
    )
  ],
  interfaces: [
    A2A::Models::AgentInterface.new(
      type:    "json-rpc",
      url:     "http://localhost:9292",
      version: "1.0"
    )
  ]
)

puts "Starting PersistentEchoAgent on http://localhost:9292"
puts "  database: #{db_path}"
puts "  existing tasks in DB: #{storage.size}"
puts "Press Ctrl-C to stop."
puts

A2A.server(agent_card: card, executor: EchoExecutor.new, storage: storage).run
