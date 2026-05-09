# Architecture

`simple_a2a` is organized into three top-level namespaces under the `A2A` module:

```
A2A
├── Models      — data classes (Task, Message, Part, Artifact, AgentCard, …)
├── Server      — HTTP server, routing, executor base, event fan-out
│   ├── App               (Roda JSON-RPC router)
│   ├── Base              (server bootstrap + Falcon runner)
│   ├── AgentExecutor     (base class for your agent logic)
│   ├── Context           (per-request helper passed to executor)
│   ├── ResumeContext     (Context + resume_message for interrupted tasks)
│   ├── TaskBroadcast     (RactorQueue-based SSE fan-out per running task)
│   ├── BroadcastRegistry (task_id → TaskBroadcast map, shared across requests)
│   ├── PushSender        (webhook delivery with JWT signing)
│   └── FalconRunner      (Falcon adapter)
├── Client      — async HTTP client
│   ├── Base    (JSON-RPC client over async/http)
│   └── SSE     (streaming subscribe + resubscribe client)
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
handle_send / handle_send_subscribe
    │  creates Task (submitted)
    │  builds Context (with TaskBroadcast as event_router)
    │
    ▼
Executor#call(ctx)          ← your code lives here
    │  ctx.task.start!
    │  ctx.emit_artifact(…)  → TaskBroadcast → RactorQueue(s) → SSE subscriber(s)
    │  ctx.task.complete!(…)
    │
    ▼
Storage#save(task)
    │
    ▼
JsonRpc::Response (task hash) → HTTP response   [tasks/send]
SSE stream closes             → HTTP body ends  [tasks/sendSubscribe / tasks/resubscribe]
```

## Key design decisions

**Zeitwerk autoloading** — all files under `lib/simple_a2a/` load on demand. The top-level module is `A2A` (not `SimpleA2a`), achieved via a custom Zeitwerk inflector.

**Async-first** — the server runs inside Falcon's async reactor. The client uses `Async::HTTP::Internet` and wraps calls in `Async { }.wait` when invoked outside a reactor, keeping the public API synchronous.

**One executor instance** — `Server::Base` holds a single executor object. For concurrent requests, executors must be stateless (or use per-call state inside `#call`).

**Pluggable storage** — `Storage::Base` defines the interface (`save`, `find`, `list`, `delete`). `find!` (raises on missing) is a convenience method on `Storage::Memory` only — not part of the required interface. Swap in Redis or PostgreSQL by subclassing and passing your implementation to `Server::Base`.

**TaskBroadcast + BroadcastRegistry** — each streaming task gets one `TaskBroadcast`, which holds one `RactorQueue` per SSE subscriber. The broadcast is registered in `BroadcastRegistry` for the duration of the task so that `tasks/resubscribe` and `tasks/cancel` can locate it by task ID. `RactorQueue#async_push` / `#async_pop` cooperate with the Falcon fiber scheduler via `sleep(0)`, keeping the event loop non-blocking. Multiple concurrent subscribers (original `sendSubscribe` and any number of `resubscribe` clients) each receive every event independently.
