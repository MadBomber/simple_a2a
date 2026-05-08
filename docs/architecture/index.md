# Architecture

`simple_a2a` is organized into three top-level namespaces under the `A2A` module:

```
A2A
├── Models      — data classes (Task, Message, Part, Artifact, AgentCard, …)
├── Server      — HTTP server, routing, executor base, event fan-out
│   ├── App          (Roda JSON-RPC router)
│   ├── Base         (server bootstrap + Falcon runner)
│   ├── AgentExecutor (base class for your agent logic)
│   ├── Context      (per-request helper passed to executor)
│   ├── ResumeContext (Context + resume_message for interrupted tasks)
│   ├── EventRouter  (TypedBus SSE fan-out)
│   ├── PushSender   (webhook delivery with JWT signing)
│   └── FalconRunner (Falcon adapter)
├── Client      — async HTTP client
│   ├── Base    (JSON-RPC client over async/http)
│   └── SSE     (streaming subscribe client)
├── Storage     — task persistence
│   ├── Base    (abstract interface)
│   └── Memory  (in-process, thread-safe)
└── JsonRpc     — JSON-RPC 2.0 layer (request/response/error)
```

## Request lifecycle

```
Client POST /
    │
    ▼
App (Roda)
    │  JSON-RPC parse + dispatch
    │
    ▼
handle_send
    │  creates Task (submitted)
    │  builds Context
    │
    ▼
Executor#call(ctx)          ← your code lives here
    │  ctx.task.start!
    │  ctx.emit_artifact(…)  → EventRouter → SSE subscribers
    │  ctx.task.complete!(…)
    │
    ▼
Storage#save(task)
    │
    ▼
JsonRpc::Response (task hash) → HTTP response
```

## Key design decisions

**Zeitwerk autoloading** — all files under `lib/simple_a2a/` load on demand. The top-level module is `A2A` (not `SimpleA2a`), achieved via a custom Zeitwerk inflector.

**Async-first** — the server runs inside Falcon's async reactor. The client uses `Async::HTTP::Internet` and wraps calls in `Async { }.wait` when invoked outside a reactor, keeping the public API synchronous.

**One executor instance** — `Server::Base` holds a single executor object. For concurrent requests, executors must be stateless (or use per-call state inside `#call`).

**Pluggable storage** — `Storage::Base` defines the interface (`save`, `find`, `list`, `delete`). `find!` (raises on missing) is a convenience method on `Storage::Memory` only — not part of the required interface. Swap in Redis or PostgreSQL by subclassing and passing your implementation to `Server::Base`.

**EventRouter** — wraps `TypedBus::MessageBus` to provide per-task SSE channels. Channels are opened on first publish and closed when the SSE connection ends. `subscribe` transparently unwraps `TypedBus::Delivery` and calls `ack!`.
