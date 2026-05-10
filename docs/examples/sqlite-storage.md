# 11 SQLite3 Persistent Storage

**Run it:**

```bash
bundle exec ruby examples/run 11_sqlite_storage
```

**What it shows:** replacing the default in-memory store with a custom `Storage::Base` subclass backed by SQLite3, proving that tasks survive a full server restart.

---

## Files

| File | Purpose |
|---|---|
| `examples/11_sqlite_storage/server.rb` | `SqliteStorage < A2A::Storage::Base` and the `PersistentEchoAgent` server |
| `examples/11_sqlite_storage/client.rb` | `populate` phase (send tasks, save IDs) and `verify` phase (fetch tasks after restart) |
| `examples/11_sqlite_storage/run` | Two-phase lifecycle: populate → stop → restart → verify → cleanup |
| `examples/11_sqlite_storage/Gemfile` | Extends the project gemspec + adds `sqlite3` |
| `examples/11_sqlite_storage/Brewfile` | Declares the `sqlite3` binary dependency for Homebrew |

---

## Dependencies

This demo has its own `Gemfile` and `Brewfile`. The `run` script handles setup before spawning anything:

1. **Binary check** — verifies `sqlite3` is on `$PATH`; on macOS runs `brew bundle install --file=Brewfile` if it is not. Other platforms must provide the binary.
2. **Gem install** — runs `bundle install` with the local `Gemfile`, which uses `gemspec path: "../../"` to pull in all project dependencies plus `sqlite3`.

Once setup completes, `server.rb` can simply `require "sqlite3"` with no inline install logic.

---

## The two-phase demo

**Phase 1 — populate**

The server starts with an empty database. The client sends three tasks (alpha, beta, gamma) and writes their IDs to a temp JSON file, then the server stops.

**Phase 2 — verify**

The server restarts pointing at the same database file. At startup it prints the existing task count (`existing tasks in DB: 3`), confirming the data survived. The client reads the saved IDs, fetches each task from the freshly booted server, and asserts all three are present and `completed`.

---

## `SqliteStorage` implementation

`SqliteStorage` subclasses `A2A::Storage::Base` and implements all five required methods:

```ruby
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

  def list
    rows = @mutex.synchronize { @db.execute("SELECT data FROM tasks ORDER BY rowid") }
    rows.map { |row| A2A::Models::Task.from_hash(JSON.parse(row[0])) }
  end

  def delete(id)
    @mutex.synchronize { @db.execute("DELETE FROM tasks WHERE id=?", [id]) }
  end
end
```

Tasks are stored as JSON blobs. `from_hash` reconstructs the full `Task` object including nested `TaskStatus`, `Artifact`, and `Part` models.

WAL mode allows concurrent readers while a write is in progress — important when multiple fibers are saving and fetching tasks simultaneously in a Falcon server.

---

## Injecting the storage

The storage instance is passed to `A2A.server` via the `storage:` keyword:

```ruby
storage = SqliteStorage.new(db_path)
A2A.server(agent_card: card, executor: EchoExecutor.new, storage: storage).run
```

No other library configuration is needed. The server's built-in RPC handlers (`tasks/get`, `tasks/list`, `tasks/cancel`, etc.) all use the injected store.

---

## Protocol coverage

| Spec section | What the demo shows |
|---|---|
| `Storage::Base` injection | `A2A.server(storage:)` accepts any `Storage::Base` subclass — no library changes needed |
| `SqliteStorage#save` | Tasks serialized to JSON and upserted via `ON CONFLICT DO UPDATE` |
| `SqliteStorage#find!` | Task fetched by ID across process boundaries; raises `TaskNotFoundError` if missing |
| `SqliteStorage#list` | All stored tasks returned in insertion order |
| `SqliteStorage#size` | Task count reported at server startup to confirm DB contents |
| Cross-restart persistence | Tasks created in server process 1 are visible to server process 2 via the shared DB file |
| WAL mode concurrency | `PRAGMA journal_mode=WAL` allows concurrent readers during writes |
| `Brewfile` / `Gemfile` pattern | Per-demo dependency files keep application code free of setup logic |

---

## Related guide

See [Custom Storage](../guides/custom-storage.md) for a detailed walkthrough of the `Storage::Base` interface and adapter patterns for other databases.
