# Compare & Contrast: `agent2agent` vs `simple_a2a`

**`agent2agent`** — https://github.com/general-intelligence-systems/agent2agent
**`simple_a2a`** — https://github.com/MadBomber/simple_a2a
**Reviewed:** 2026-05-08

---

## 1. Philosophy and Scope

| | `agent2agent` | `simple_a2a` |
|---|---|---|
| **Philosophy** | Spec-first: derive everything from the canonical `.proto` and `.json` schema files | Pragmatic: hand-craft a clean, minimal Ruby interface that covers real use cases |
| **Complexity** | Heavy — brings in protobuf parsing, JSON Schema validation, SQLite, structured logging | Lightweight — each component is a short, readable Ruby class |
| **Target user** | Teams that need the full A2A spec surface, including multi-tenant and OpenTelemetry | Individual developers or small teams who want a drop-in, understandable library |
| **License** | Apache 2.0 | MIT |
| **Ruby requirement** | >= 3.2 | >= 3.2 |
| **Namespace** | `A2A` | `A2A` (same) |
| **Gem name** | `agent2agent` | `simple_a2a` |
| **Authorship** | "A2A Contributors" (organizational) | Dewayne VanHoozer (individual) |

---

## 2. Protocol Coverage

### Operations Implemented

| Operation | `agent2agent` | `simple_a2a` |
|---|---|---|
| SendMessage / `tasks/send` | Yes | Yes |
| SendStreamingMessage / `tasks/sendSubscribe` | Yes | Yes |
| GetTask / `tasks/get` | Yes | Yes |
| ListTasks / `tasks/list` | Yes | Yes |
| CancelTask / `tasks/cancel` | Yes | Yes |
| SubscribeToTask (SSE poll of existing task) | Yes | No |
| CreateTaskPushNotificationConfig | Yes (full) | Stub only |
| GetTaskPushNotificationConfig | Yes (full) | Stub only |
| ListTaskPushNotificationConfigs | Yes (full) | Stub only |
| DeleteTaskPushNotificationConfig | Yes (full) | Stub only |
| GetExtendedAgentCard | Yes | No |

`agent2agent` implements all 11 A2A protocol operations. `simple_a2a` implements 5 core operations plus push notification stubs.

### Transport Bindings

| | `agent2agent` | `simple_a2a` |
|---|---|---|
| **JSON-RPC 2.0** | Yes — `POST /a2a` | Yes — `POST /` |
| **HTTP+JSON REST** | Yes — `POST /message:send`, `GET /tasks/{id}`, etc. | No |
| **Agent Discovery** | `GET /.well-known/agent-card.json` (spec-compliant path) | `GET /agentCard` (non-standard path) |

`agent2agent` supports both the JSON-RPC and REST wire formats from the spec. `simple_a2a` is JSON-RPC only. The agent card path difference means `simple_a2a` is not spec-compliant for discovery.

### Protocol Versioning

`simple_a2a` checks the `A2A-Version` request header and rejects unsupported versions (`SUPPORTED_VERSIONS = %w[1.0 0.3]`) with a JSON-RPC error response. `agent2agent` does not implement version negotiation.

### Multi-Tenant Paths

`agent2agent` supports tenant-prefixed route variants (`/{tenant}/message:send`, etc.) built into its REST binding. `simple_a2a` has no multi-tenant concept, but its `MultiAgent` class achieves path-based isolation via `Rack::URLMap`.

---

## 3. Server Architecture

### `agent2agent` — Rack Middleware Chain

```
Rack::URLMap
  /.well-known/agent-card.json  →  AgentCardHandler
  /a2a                          →  Bindings::JsonRpc → Server::Env → Server::Triage → Server::Dispatcher
  /                             →  Bindings::Rest    → Server::Env → Server::Triage → Server::Dispatcher
```

- Each operation has its own handler class in `lib/a2a/server/` (11 handler files)
- `Triage` resolves the target operation from either the JSON-RPC method name or the REST verb+path — derived from `data/a2a.proto` at load time, not hard-coded
- `Dispatcher` routes `env["a2a.operation"]` to registered handler objects via duck-typing

### `simple_a2a` — Roda App

```
A2A::Server::App < Roda
  GET  /agentCard   →  return agent_card.to_h
  POST /            →  parse JSON-RPC, dispatch by method name (case statement)
    tasks/sendSubscribe  →  handle_send_subscribe (SSE)
    tasks/send           →  handle_send
    tasks/get            →  handle_get
    tasks/list           →  handle_list
    tasks/cancel         →  handle_cancel
    tasks/pushNotification/*  →  handle_push_* (stubs)
```

- Uses Roda plugins: `json`, `json_parser`, `halt`, `all_verbs`
- Dispatch is a `case rpc_req.method` in `App#dispatch` — explicit and readable but requires a code change for each new operation
- `Server::Base` is the public entry point; it creates a fresh anonymous `App` subclass per instance so class-level state doesn't bleed between servers

**Key difference:** `agent2agent` is extensible via proto-driven operation registration; `simple_a2a` is explicit but static. Adding a new operation in `simple_a2a` means editing `dispatch`; in `agent2agent`, it follows automatically from the proto file.

---

## 4. Agent / Executor Model

### `agent2agent` — DSL with `on` blocks

```ruby
agent = A2A::Agent.new do
  on "SendMessage", "SendStreamingMessage" do |context|
    task = context.store.create(context.request)
    stream = context.stream
    Async do
      result = robot.run(context.request.params[:message])
      context.store.complete(task.id, result)
      stream.event(result, type: "result")
      stream.finish
    end
    context.respond(task)
  end
end
server = A2A::Server.new
server.register(agent)
```

The `Agent` DSL maps operation names to blocks. Multiple operations can share one handler. The `Context` object exposes `respond(result)`, `stream`, `store`, `agent_card`, and `request`. The `respond` call returns a synchronous response; SSE is opt-in via `context.stream`.

### `simple_a2a` — Abstract class with `#call` / `#cancel`

```ruby
class MyExecutor < A2A::Server::AgentExecutor
  def call(context)
    context.task.working!
    context.emit_status
    result = do_work(context.message)
    context.task.complete!(result)
    context.emit_status(final: true)
  end
end

server = A2A::Server::Base.new(
  agent_card: card,
  executor:   MyExecutor.new,
  storage:    A2A::Storage::Memory.new
)
server.run
```

`AgentExecutor` is an abstract class with `#call(context)` and a default `#cancel(context)` that calls `task.cancel!`. The executor is responsible for advancing task state explicitly. The `Context` object exposes `task`, `message`, `storage`, `event_router`, `save_task`, `emit_status`, and `emit_artifact`.

**Key difference:** `agent2agent`'s DSL is more concise for simple cases but less obvious for control flow. `simple_a2a`'s abstract class pattern is more explicit about what the implementer must do and is easier to test in isolation.

---

## 5. Context Object

| Method / Attribute | `agent2agent` | `simple_a2a` |
|---|---|---|
| Access the task | via `context.store` | `context.task` (direct reference) |
| Send a response | `context.respond(result)` | return value from `#call` (App handles it) |
| SSE stream | `context.stream` | SSE handled transparently by App; executor yields events via `emit_status` / `emit_artifact` |
| Task store | `context.store` | `context.storage` |
| Agent card | `context.agent_card` | not on context — on `App` class |
| Inbound message | `context.request` | `context.message` |
| Persist task | via `store.complete(...)` | `context.save_task` or `context.emit_status` (auto-saves) |
| Emit status event | N/A (store methods do it) | `context.emit_status(final: false)` |
| Emit artifact event | N/A | `context.emit_artifact(artifact, append:, last_chunk:)` |

`simple_a2a`'s context makes task-state advancement and event emission first-class operations. `agent2agent`'s context is thinner on the executor side — more work goes through the store.

---

## 6. Schema and Models

### `agent2agent` — Spec-Driven Dynamic Classes

- Loads `data/a2a.json` (47-type JSON Schema bundle, 73 KB) at startup
- Dynamically generates one `Definition` subclass per schema type
- Each class provides: snake_case readers, `to_h` (camelCase output), `valid?`/`valid!` (full JSON Schema validation via `json_schemer`), and `==`
- Also parses `data/a2a.proto` (34 KB) to derive operation metadata, HTTP bindings, and streaming flags
- **Validation:** full JSON Schema compliance against the official A2A spec

### `simple_a2a` — Hand-Written `Models::Base` DSL

```ruby
class Message < Base
  attribute :role,  type: String,    required: true
  attribute :parts, type: [Part]
  attribute :metadata
end
```

- ~15 hand-written model classes in `lib/simple_a2a/models/`
- `Models::Base` provides: `attribute` macro, `from_hash` (with camelCase/snake_case coercion), `to_h`, `to_json`, `valid?` (required-field check only), `==`
- Type coercion handles nested models and arrays of models
- **Validation:** only checks `required:` fields; no JSON Schema enforcement

**Key difference:** `agent2agent` stays in sync with the official spec automatically (update the JSON/proto files, get new model classes). `simple_a2a` requires manual updates when the spec changes but is far easier to read and debug. `simple_a2a`'s validation is deliberately minimal — it trusts that callers pass valid data.

---

## 7. SSE Streaming

Both use `Protocol::HTTP::Body::Writable` as the SSE body — the right approach for Falcon compatibility.

### `agent2agent`

- `A2A::SSE::Stream < Protocol::HTTP::Body::Writable`
- Two subclasses: `JsonRpcStream` (wraps events in JSON-RPC envelope) and `RestStream` (plain event format)
- `stream.event(hash, type: "result")` writes formatted SSE chunks
- `stream.finish` calls `close_write`
- The executor has direct access to the stream via `context.stream`

### `simple_a2a`

- Uses `Protocol::HTTP::Body::Writable` directly, not subclassed
- In `handle_send_subscribe`, an anonymous object (duck-typed router) is created inline that writes SSE-formatted JSON-RPC events to the writable body
- The executor runs in a sibling `Async::Task`; it calls `emit_status` / `emit_artifact` which publish to the anonymous router, which writes to the writable body
- `output.close_write` is called in the `ensure` block

**Key difference:** `agent2agent`'s stream is a first-class object the executor interacts with directly. `simple_a2a`'s SSE wiring is internal to `App` — the executor emits domain events and the App translates them to SSE. The `simple_a2a` approach is cleaner for the executor author but the anonymous-object pattern in `handle_send_subscribe` is the trickiest code in the library.

---

## 8. Task Storage

### `agent2agent`

Two implementations:
- `A2A::TaskStore` — in-memory, mutex-synchronized
- `A2A::Sqlite` (~16 KB) — WAL mode, indexed, production-ready, fiber-safe via `Async::Queue` pub/sub

Both include integrated pub/sub (`Store::PubSub`) and webhook delivery (`Store::Webhooks`). Pub/sub uses `Async::Queue` per task subscriber — fiber-safe without locks.

### `simple_a2a`

One implementation:
- `Storage::Memory` — in-memory, mutex-synchronized (`@mutex = Mutex.new`)
- `Storage::Base` — abstract base class defines the interface: `save`, `find`, `find!`, `delete`, `list`, `size`, `clear`

No persistent storage. Pub/sub is separated from storage into `EventRouter`.

**Key difference:** `agent2agent` ships production storage out of the box. `simple_a2a` provides the extension interface but the implementer must write their own persistent store. `agent2agent`'s storage and pub/sub are tightly coupled; `simple_a2a` separates them.

---

## 9. Pub/Sub and Event Routing

### `agent2agent` — `Store::PubSub` with `Async::Queue`

- Each task gets an `Async::Queue` per subscriber
- `nil` sentinel signals end-of-stream
- Fully fiber-safe — no locks needed under Falcon's fiber scheduler
- Integrated into the task store; the `SubscribeToTask` operation connects clients to these queues

### `simple_a2a` — `EventRouter` wrapping `TypedBus`

```ruby
@bus = TypedBus::MessageBus.new
@bus.add_channel(task_id.to_sym, type: nil, timeout: nil)
@bus.publish(sym, event)
@bus.subscribe(sym) { |delivery| block.call(delivery.message); delivery.ack! }
```

- Channels are keyed by task ID (as Symbol)
- Typed, ack-based message delivery via `typed_bus` gem
- `EventRouter` is dependency-injected — in SSE mode, `App` swaps in an anonymous router that writes directly to the `Writable` body

**Key difference:** `agent2agent`'s `Async::Queue` is fiber-native and simpler internally. `simple_a2a`'s `TypedBus` adds ack semantics and typing but introduces an external dependency. The swap-in anonymous router for SSE is a clever workaround for the fact that `TypedBus` isn't directly wired to the HTTP body.

---

## 10. Client

### `agent2agent` — Dynamically Generated Methods

- Methods generated from `Proto.operations` mapped to snake_case
- Uses `Async::HTTP::Internet` for non-blocking HTTP
- JSON-RPC 2.0 requests to `/a2a`
- Auto-incrementing request IDs
- Also fetches `/.well-known/agent-card.json`

### `simple_a2a` — Hand-Written Named Methods

```ruby
client.agent_card
client.send_task(message: msg)
client.get_task(task_id)
client.list_tasks
client.cancel_task(task_id)
```

- `Async::HTTP::Internet` — same concurrency model
- Context-aware: works inside an existing `Async::Task` or creates its own
- Methods return typed `Models::*` objects
- Also includes `Client::SSE` for consuming streaming responses

**Key difference:** `agent2agent`'s dynamic generation means new operations are available automatically when the proto file is updated. `simple_a2a`'s hand-written methods are easier to introspect, document, and test, but require manual additions for new operations. `simple_a2a`'s async context awareness (using existing task if present, creating one if not) is a practical improvement.

---

## 11. Push Notifications

### `agent2agent`

- Full async webhook delivery via `Store::Webhooks` + `Async::HTTP`
- Per-task push notification config CRUD with full protocol storage
- Webhook auth: `Authorization: Bearer <credentials>` + optional `X-A2A-Notification-Token`
- Runs delivery in background fibers

### `simple_a2a`

- `PushSender` class with real HTTP delivery via `Net::HTTP`
- JWT signing (RS256) with payload hash, configurable private key + key ID + issuer
- Supports `bearer` (JWT), `token` (static), or custom header auth schemes
- 5/10 second open/read timeout
- Push notification config CRUD operations are stubs — they respond successfully but do not store configs

**Key difference:** `agent2agent` has full push notification infrastructure. `simple_a2a` has a capable delivery mechanism (`PushSender`) but the server-side config storage is not implemented — the stubs accept requests without persisting anything. A real push notification flow requires the implementer to wire `PushSender` into the executor manually.

---

## 12. Multi-Agent Support

### `agent2agent`

```ruby
server = A2A::Server.new
server.register(agent1)
server.register(agent2)
```

Multiple agents registered on a single server; the dispatcher routes to the correct agent based on its declared operations.

### `simple_a2a`

```ruby
A2A::Server::MultiAgent.new(
  agents: {
    "/anthropic" => { agent_card: card1, executor: exec1 },
    "/openai"    => { agent_card: card2, executor: exec2 }
  },
  port: 9292
).run
```

`MultiAgent` uses `Rack::URLMap` — each agent gets its own URL path prefix. Each agent gets a fresh anonymous `App` subclass so class-level config state doesn't bleed.

**Key difference:** `agent2agent` shares a single endpoint; agents are distinguished by operation. `simple_a2a` isolates agents at the URL level — different agents at different paths. The `Rack::URLMap` approach is architecturally cleaner for true multi-agent isolation.

---

## 13. Dependencies

### Runtime comparison

| Gem | `agent2agent` | `simple_a2a` |
|---|---|---|
| `async` | Yes | Yes |
| `async-http` | Yes | Yes |
| `rack` | Yes | Yes |
| `protocol-http` | Yes (explicit) | Yes (via falcon) |
| `falcon` | Dev only | Yes (runtime) |
| `roda` | No | Yes |
| `google-protobuf` | Yes | No |
| `json_schemer` | Yes | No |
| `sqlite3` | Yes | No |
| `console` | Yes | No |
| `scampi` | Yes (inline tests) | No |
| `jwt` | No | Yes |
| `simple_flow` | No | Yes |
| `typed_bus` | No | Yes |
| `zeitwerk` | No | Yes |
| `logger` | No | Yes |

`agent2agent` pulls in protobuf, JSON Schema validation, and SQLite. `simple_a2a` pulls in Roda, JWT, and two smaller gems (`typed_bus`, `simple_flow`). `agent2agent` is heavier in binary dependencies (native extensions: `google-protobuf`, `sqlite3`). `simple_a2a`'s heavier non-obvious dependency is `typed_bus`, which is a less-established gem.

---

## 14. Observability and Tracing

| | `agent2agent` | `simple_a2a` |
|---|---|---|
| **Structured logging** | `console` gem throughout | `A2A.logger` (stdlib Logger); warn-level in PushSender |
| **Distributed tracing** | `lib/traces/provider/a2a/` — OpenTelemetry-compatible spans for bindings and dispatcher | None |
| **Operation counters** | `Store::Processor` tracks call/complete/failed counts | None |

`agent2agent` is observability-ready out of the box for teams running distributed agent systems. `simple_a2a` has minimal logging.

---

## 15. Testing Strategy

### `agent2agent` — Inline Tests via `scampi`

- Tests live inside source files, co-located with the code they test
- `test do ... end` blocks with `.should`-style assertions
- No separate `test/` directory

### `simple_a2a` — Minitest in `test/`

- Separate `test/` directory with conventional Minitest structure
- 98% code coverage measured via `simplecov`
- `rack-test` for HTTP-level integration tests
- Separate files per module: `test/server/test_app.rb`, `test/server/test_app_sse.rb`, `test/integration/test_round_trip.rb`, etc.

**Key difference:** `scampi` inline tests reduce context-switching but non-standard tooling makes CI integration harder. Minitest is familiar, with rich ecosystem support. `simple_a2a`'s 98% coverage is a strong signal of test completeness.

---

## 16. Examples

| | `agent2agent` | `simple_a2a` |
|---|---|---|
| Count | 6 | 3 |
| Basic usage | Yes | Yes (`01_basic_usage/`) |
| Streaming | Yes | Yes (`02_streaming/`) |
| LLM integration | No | Yes (`03_llm_research/`) |
| Async/background jobs | Yes | No |
| Multi-turn conversation | Yes | No |
| Multi-agent | Yes | No (but `MultiAgent` class exists) |
| Push notifications | Yes | No |
| Docker/Compose | Yes | No |

---

## 17. Summary Assessment

### Where `agent2agent` wins

1. **Spec completeness** — all 11 operations, both transport bindings, spec-compliant agent card path
2. **Production storage** — SQLite store ships out of the box; no extra code to write
3. **Spec fidelity** — schema and routing auto-update from the canonical proto/JSON files
4. **Observability** — OpenTelemetry instrumentation built in
5. **Multi-turn support** — `STATE_INPUT_REQUIRED` state machine entry is formally modeled
6. **Push notification infrastructure** — full config CRUD + async webhook delivery
7. **Example breadth** — async jobs, multi-turn, multi-agent, push notifications all demonstrated

### Where `simple_a2a` wins

1. **Readability** — every class is short, explicit, and readable without spec knowledge
2. **Testability** — abstract `AgentExecutor` is easy to test in isolation; 98% coverage
3. **Protocol versioning** — `A2A-Version` header negotiation not present in `agent2agent`
4. **Multi-agent isolation** — path-based isolation via `Rack::URLMap` is architecturally cleaner
5. **Client ergonomics** — async context awareness; returns typed model objects
6. **JWT push auth** — RS256 JWT signing for webhook delivery is more sophisticated
7. **Lighter binary footprint** — no native protobuf or SQLite extensions required for the base gem
8. **Conventional test structure** — Minitest + simplecov is standard, CI-friendly

### The fundamental trade-off

`agent2agent` trades complexity for spec completeness and auto-synchronization with the A2A specification. It's the right choice for teams that need the full protocol surface and are running under Falcon with Async throughout.

`simple_a2a` trades spec completeness for simplicity and explicitness. It's the right choice when you want to understand every line of your A2A dependency, need conventional testing tools, or are embedding an A2A server into an existing Ruby application without committing to a full fiber-based async stack at every layer.

### Gaps in `simple_a2a` worth closing

1. **Agent card path** — `/agentCard` should be `/.well-known/agent-card.json` for spec compliance
2. **REST transport binding** — currently JSON-RPC only; REST endpoints would enable broader interop
3. **`SubscribeToTask`** — SSE stream on an existing task is missing; only `sendSubscribe` (new task + stream) is supported
4. **`GetExtendedAgentCard`** — not implemented
5. **Push notification config persistence** — `PushSender` exists but config CRUD stubs don't store anything
6. **Persistent storage** — `Storage::Base` interface is ready; a SQLite or file-backed implementation would make `simple_a2a` production-ready without adding native extensions
