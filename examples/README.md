# simple_a2a — Example Applications

Eleven runnable demo applications that exercise the gem end-to-end. Each demo
pairs a `server.rb` and a `client.rb` so both sides of the A2A protocol are
visible in one place.

---

## How to run

### Automated (recommended)

From the repository root, use the `run` launcher. It starts the server,
waits for it to accept connections, runs the client, then shuts the server
down cleanly.

```bash
bundle exec ruby examples/run <demo-name>
```

Examples:

```bash
bundle exec ruby examples/run 01_basic_usage
bundle exec ruby examples/run 05_cancellation
```

The trailing slash shown by tab-completion is accepted: `./run 01_basic_usage/`
works just as well.

### Manual (two terminals)

Start the server in one terminal, then run the client in a second:

```bash
# terminal 1
bundle exec ruby examples/01_basic_usage/server.rb

# terminal 2
bundle exec ruby examples/01_basic_usage/client.rb
```

All demos bind the A2A server to `http://localhost:9292` unless noted
otherwise.

### Demo 03 — LLM Research (special setup)

Demo 03 requires API keys and additional gems that are not part of the gem's
normal dependency set:

```bash
bundle add ruby_llm async-http-faraday sinatra
export ANTHROPIC_API_KEY=your_key_here
export OPENAI_API_KEY=your_key_here
bundle exec ruby examples/run 03_llm_research
```

The demo has its own lifecycle script that starts both the A2A server
(port 9292) and a Sinatra web client (port 4567). Open
`http://localhost:4567` in a browser after both processes start.

---

## Prerequisites

All other demos run with just the gem's standard development setup:

```bash
bundle install
bundle exec ruby examples/run 01_basic_usage
```

No additional gems or environment variables are required.

---

## Demo index

| # | Name | A2A features demonstrated |
|---|------|--------------------------|
| 01 | Basic Usage | Agent card discovery, `tasks/send`, `tasks/get`, `tasks/list`, error handling |
| 02 | Streaming | `tasks/sendSubscribe`, SSE, incremental artifact chunks |
| 03 | LLM Research | `multi_server`, parallel SSE agents, evaluator pattern, web client |
| 04 | Resubscribe | `tasks/resubscribe`, concurrent SSE subscribers, mid-stream join |
| 05 | Cancellation | `tasks/cancel`, concurrent tasks, task lifecycle |
| 06 | Push Notifications | `tasks/pushNotification/set/get/delete/list`, webhook delivery |
| 07 | Agent Chaining | Agent-to-agent calls via `A2A.client` inside an executor |
| 08 | Interrupted States | `input_required`, `auth_required`, multi-turn conversations |
| 09 | Multipart | `Part.text`, `Part.json`, `Part.binary`, `Part.from_url` |
| 10 | Auth Headers | `A2A.client(headers:)`, Bearer token middleware |
| 11 | SQLite Storage | `Storage::Base` injection, SQLite3 WAL persistence, cross-restart task survival |

---

## Demos

### 01 — Basic Usage

```bash
bundle exec ruby examples/run 01_basic_usage
```

The foundational request/response pattern: a client sends messages to an
agent and receives completed artifacts in the HTTP response body.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| Agent Card discovery | Client calls `GET /agentCard` and reads the agent's name, version, description, and skills |
| `tasks/send` | Synchronous task submission — executor runs to completion before the HTTP response returns |
| `tasks/get` | Client retrieves a previously completed task by ID |
| `tasks/list` | Client fetches all tasks on the server |
| Error responses | Client requests a non-existent task ID; server returns `TASK_NOT_FOUND` JSON-RPC error |
| `AgentCard` model | `name`, `version`, `description`, `skills`, `interfaces`, `capabilities` |
| `Message` model | `Message.user(text)` builds a user-role message with a text part |
| `Artifact` model | Completed task carries a named artifact with a text part |

---

### 02 — Streaming

```bash
bundle exec ruby examples/run 02_streaming
```

The server streams a long article word-by-word at 600 words per minute.
The client receives the text incrementally as Server-Sent Events rather
than waiting for the full response.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `tasks/sendSubscribe` | Client opens a persistent SSE connection; server streams events for the duration of the task |
| `TaskStatusUpdateEvent` | `working` event emitted when execution starts; `completed` final event signals the stream is done |
| `TaskArtifactUpdateEvent` | Each word arrives as a separate artifact chunk with `append: true` and `lastChunk: true` on the final word |
| `AgentCapabilities.streaming` | `true` in the agent card, advertised to clients before subscription |
| SSE transport | `Content-Type: text/event-stream`, `data:` frames, `\n\n` event boundaries |

---

### 03 — Multi-Agent LLM Research

```bash
bundle exec ruby examples/run 03_llm_research
```

Three agents on one server: an Anthropic researcher (Claude), an OpenAI
researcher (GPT), and an evaluator. The CLI client queries both researchers
in parallel then sends their combined output to the evaluator. A Sinatra web
client provides a browser UI with side-by-side streaming panels.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `A2A.multi_server` | Three agents hosted on one port under `/anthropic`, `/openai`, and `/evaluator` path prefixes |
| `tasks/sendSubscribe` | Both researcher agents stream token-by-token responses via SSE |
| Parallel agent calls | CLI client runs two SSE subscriptions concurrently using Ruby threads |
| Evaluator pattern | One agent's output is used as the input message to a downstream agent |
| `AgentCard.interfaces` | Each agent card declares its own URL path so clients can target individual agents |
| `AgentCapabilities.streaming` | `true` on all three agents |

**Requires:** `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, plus `ruby_llm`,
`async-http-faraday`, and `sinatra`.

---

### 04 — Resubscribe

```bash
bundle exec ruby examples/run 04_resubscribe
```

A multi-step analysis task runs on the server. A first subscriber attaches
from the beginning via `tasks/sendSubscribe`. A second subscriber attaches
mid-stream via `tasks/resubscribe` and receives the current task snapshot
followed by all remaining events. Both streams close cleanly when the task
completes.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `tasks/resubscribe` | Second client joins an in-flight SSE stream using the task ID |
| Task snapshot on join | First event delivered to a resubscriber is the current `Task` object, not a status update |
| Concurrent subscribers | Two independent SSE connections receive the same broadcast events |
| `BroadcastRegistry` | Server maps task IDs to live broadcasts so resubscribers can locate the stream |
| `TaskStatusUpdateEvent` | `working` and `completed` (final) events received by both subscribers |
| `TaskArtifactUpdateEvent` | Each analysis step delivered as a discrete artifact |

---

### 05 — Cancellation

```bash
bundle exec ruby examples/run 05_cancellation
```

Three tasks run concurrently via `tasks/sendSubscribe`. After three seconds,
one task is cancelled via `tasks/cancel` while the other two complete
normally. The client verifies the final states of all three tasks.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `tasks/cancel` | Client sends a cancel request by task ID while the task is mid-execution |
| `canceled` terminal state | Task B transitions to `canceled`; its SSE stream receives a final status event and closes |
| Concurrent task isolation | Tasks A and C are unaffected by the cancellation of task B |
| `AgentExecutor#cancel` | Default implementation calls `task.cancel!` and emits a final status event |
| `TaskState` lifecycle | `submitted → working → canceled` vs `submitted → working → completed` |
| Executor cooperative cancellation | Executor checks `ctx.task.terminal?` between steps and exits early when cancelled |

---

### 06 — Push Notifications

```bash
bundle exec ruby examples/run 06_push_notifications
```

The client registers a local webhook receiver on port 9293, submits a task,
then registers the webhook URL via the push notification RPC methods. The
server delivers an HTTP POST to the webhook after each step — the client
holds no open SSE connection and receives all updates out-of-band.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `tasks/pushNotification/set` | Client registers a `PushNotificationConfig` containing a webhook URL |
| `tasks/pushNotification/get` | Client confirms the config is stored by retrieving it by task ID |
| `tasks/pushNotification/list` | Client lists all registered push configs on the server |
| `tasks/pushNotification/delete` | Client removes the config; list confirms zero configs remain |
| `PushNotificationConfig` model | `webhookUrl` and optional `authenticationInfo` fields |
| `PushSender` | Server delivers `TaskStatusUpdateEvent` payloads as HTTP POSTs to the webhook URL |
| `AgentCapabilities.push_notifications` | `true` in the agent card; server rejects push RPC calls if `false` |
| Out-of-band delivery | Client receives progress updates without maintaining any persistent connection |

---

### 07 — Agent Chaining

```bash
bundle exec ruby examples/run 07_agent_chaining
```

Three agents share one port. The `PipelineAgent` executor calls the
`ReverseAgent` and `ShoutAgent` in sequence using `A2A.client` — the same
client interface an external caller would use. The top-level client speaks
only to the pipeline; the internal calls are invisible to it.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| Agent-to-agent delegation | An executor uses `A2A.client` to call peer agents during task execution |
| `A2A.multi_server` | Three agents hosted at `/reverse`, `/shout`, `/pipeline` on one port |
| Agent Card discovery | Client discovers all three cards; pipeline card describes its composed capability |
| `tasks/send` | Sub-agents are called synchronously within the pipeline executor's fiber |
| Protocol transparency | Internal A2A calls use the same JSON-RPC wire format as external calls |
| Composability | Any agent can act as both a server (to its caller) and a client (to its dependencies) |

---

### 08 — Interrupted States

```bash
bundle exec ruby examples/run 08_interrupted_states
```

Two agents demonstrate the two interrupted task states. An `OrderAgent` uses
`input_required` to ask what the user wants before completing the order. A
`VaultAgent` uses `auth_required` to demand a token before revealing
protected data, staying blocked on a wrong token and unlocking on the correct
one. Each conversational turn is a separate `tasks/send` call threaded by
`message.context_id`.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `input_required` state | Task transitions to an interrupted state; `status.message` carries the question |
| `auth_required` state | Task blocks until the client provides valid credentials |
| Multi-turn conversations | Each follow-up is a new `tasks/send` carrying the same `context_id` |
| `Message.context_id` | Executor uses the message's `contextId` field to thread state across separate task calls |
| `TaskState` interrupted vs terminal | `input_required` and `auth_required` are non-terminal; the task can still complete |
| Rejection on bad auth | VaultAgent stays in `auth_required` on a wrong token, demonstrating repeated challenge |

---

### 09 — Multipart Artifacts

```bash
bundle exec ruby examples/run 09_multipart
```

A single artifact carries four parts of different types: a plain text summary,
a structured JSON hash, a base64-encoded binary CSV, and a URL reference. The
client inspects each part using the predicate methods and processes each type
appropriately.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `Part.text` | Plain prose with `media_type: "text/plain"` |
| `Part.json` | Structured data as a Ruby Hash; serialized as a JSON object in the artifact |
| `Part.binary` | Raw bytes base64-encoded for transport; `decoded_bytes` restores the original |
| `Part.from_url` | URL reference with `media_type` and `filename`; no content is inlined |
| `Part` predicates | `text?`, `json?`, `raw?`, `url?` allow type-safe dispatch on the receiving end |
| Multi-part `Artifact` | One artifact contains all four parts; clients can select the representation they need |
| `Artifact.name` | Named artifact (`"report"`) for client-side identification |

---

### 10 — Authentication Headers

```bash
bundle exec ruby examples/run 10_auth_headers
```

The server wraps its Rack app in a Bearer token middleware. Agent card
discovery (`GET /agentCard`) is left public; all RPC calls (`POST /`) require
`Authorization: Bearer <token>`. Two clients are created — one without
headers and one with — demonstrating that the `headers:` option on
`A2A.client` is the injection point for any custom auth scheme.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `A2A.client(headers:)` | `headers: { "Authorization" => "Bearer token" }` appended to every request |
| `AgentCard` public discovery | `GET /agentCard` succeeds without authentication — agents are discoverable |
| Bearer token authentication | `Authorization: Bearer <token>` header checked on all POST (RPC) requests |
| Rack middleware composition | `BearerAuthMiddleware.new(rack_app, token:)` wraps the standard app without library changes |
| JSON-RPC error on rejection | Middleware returns a well-formed JSON-RPC error body so the client can rescue `A2A::Error` |
| Header flexibility | The same `headers:` option supports API keys, custom schemes, and any HTTP header |

---

### 11 — SQLite3 Persistent Storage

```bash
bundle exec ruby examples/run 11_sqlite_storage
```

The server injects a `SqliteStorage` instance — a custom `Storage::Base` subclass
backed by SQLite3 — instead of the default in-memory store. The demo runs in two
phases managed by a custom `run` script to prove that tasks survive a full server
restart:

1. **Populate** — server starts, three tasks are sent and stored in `tasks.db`, task
   IDs are written to a temp JSON file, server stops.
2. **Verify** — server restarts with the same `tasks.db`, client reads the saved IDs
   and fetches each task from the freshly booted server, confirming all three tasks
   are present with state `completed`.

The `SqliteStorage` implementation uses WAL mode and a mutex for safe concurrent
access. Dependencies are declared in conventional tool files kept alongside the
demo rather than inlined into application code:

- **`Brewfile`** — declares the `sqlite3` binary dependency; the `run` script
  calls `brew bundle install` on macOS if the binary is not already present.
  Other platforms must provide the binary themselves.
- **`Gemfile`** — uses `gemspec path: "../../"` to pull in all of the project's
  own dependencies, then adds `sqlite3`. The `run` script calls `bundle install`
  with this Gemfile before spawning either server phase, so `server.rb` can
  simply `require "sqlite3"` with no inline gem-install logic.

**Protocol specification coverage:**

| Spec section | What the demo shows |
|---|---|
| `Storage::Base` injection | `A2A.server(storage:)` accepts any `Storage::Base` subclass — no library changes needed |
| `SqliteStorage#save` | Tasks serialized to JSON and upserted into SQLite via `ON CONFLICT DO UPDATE` |
| `SqliteStorage#find!` | Task fetched by ID across process boundaries; raises `TaskNotFoundError` if missing |
| `SqliteStorage#list` | All stored tasks returned in insertion order |
| `SqliteStorage#size` | Task count reported at server startup to confirm DB contents |
| Cross-restart persistence | Tasks created in server process 1 are visible to server process 2 via the shared DB file |
| WAL mode concurrency | `PRAGMA journal_mode=WAL` allows concurrent readers during writes |
| `Brewfile` / `Gemfile` pattern | Per-demo dependency files keep application code free of setup logic |
