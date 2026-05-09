# Server API

## Server::Base

The server entry point. Creates and wires all server components, then runs Falcon.

```ruby
server = A2A::Server::Base.new(
  agent_card:  card,        # A2A::Models::AgentCard (required)
  executor:    MyExecutor.new,  # A2A::Server::AgentExecutor subclass (required)
  storage:     A2A::Storage::Memory.new,  # default
  push_sender: nil,         # A2A::Server::PushSender instance, optional
  host:        "localhost", # default
  port:        9292         # default
)

server.run          # blocks — starts Falcon
server.rack_app     # returns the Rack app (useful for embedding in other servers)
```

Convenience factory:

```ruby
server = A2A.server(agent_card: card, executor: MyExecutor.new)
server.run
```

---

## Server::MultiAgent

Hosts multiple A2A agents in one Falcon process by mounting each agent at its own URL path. Use this when you want independent AgentCards, executors, storage, and SSE channels behind one port.

```ruby
server = A2A.multi_server(
  agents: {
    "/anthropic" => { agent_card: anthropic_card, executor: AnthropicExecutor.new },
    "/openai"    => { agent_card: openai_card,    executor: OpenAIExecutor.new },
    "/evaluator" => { agent_card: evaluator_card, executor: EvaluatorExecutor.new }
  },
  host: "localhost",
  port: 9292
)

server.run
```

Each entry in `agents` accepts the same core configuration used by `Server::Base`:

| Key | Required | Description |
|---|---|---|
| `:agent_card` | Yes | AgentCard returned by that path's `/agentCard` endpoint |
| `:executor` | Yes | Executor that handles requests for that path |
| `:storage` | No | Storage backend for that path; defaults to `A2A::Storage::Memory.new` |
| `:push_sender` | No | Push notification sender for that path |

For a runnable example, see the [Multi-Agent LLM Research demo](../../examples/llm-research.md).

---

## Server::AgentExecutor

Base class for your agent logic. Subclass and implement `#call`:

```ruby
class MyExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    # ctx is an A2A::Server::Context
    input = ctx.message.text_content
    ctx.task.start!
    # … do work …
    ctx.task.complete!(artifacts: [ … ])
  end

  # Optional: handle task cancellation
  def cancel(ctx)
    # default implementation calls ctx.task.cancel! and emits a final status event
    super
  end
end
```

`#call` runs synchronously inside the Falcon reactor. Long-running work should use `Async::Task` internally to stay non-blocking.

---

## Server::Context

Passed to `AgentExecutor#call`. Provides access to the request and helper methods.

```ruby
ctx.task          # => A2A::Models::Task
ctx.message       # => A2A::Models::Message (the incoming message)
ctx.storage       # => A2A::Storage::Base
ctx.event_router  # => A2A::Server::TaskBroadcast (duck-typed — responds to #publish)
ctx.config        # => Hash (arbitrary per-request config, default {})

ctx.save_task           # persists task to storage
ctx.emit_status(final: false)          # publishes TaskStatusUpdateEvent
ctx.emit_artifact(artifact, append: false, last_chunk: false)  # publishes TaskArtifactUpdateEvent
```

---

## Server::ResumeContext

A `Context` subclass for resumed tasks (after `input_required` or `auth_required`).

```ruby
# Additional attribute:
ctx.resume_message   # => A2A::Models::Message (the new input from the user)
```

---

## Server::TaskBroadcast

Per-task lock-free SSE fan-out. One `TaskBroadcast` is created per streaming task and held in the `BroadcastRegistry` for the duration of that task. You rarely interact with this directly — use `ctx.emit_status` and `ctx.emit_artifact` instead.

```ruby
broadcast = A2A::Server::TaskBroadcast.new

queue = broadcast.subscribe           # returns a RactorQueue for this subscriber
broadcast.publish(task_id, event)     # fans event out to all subscriber queues
broadcast.error("something failed")  # fans a BroadcastError sentinel to all queues
broadcast.close                       # fans the DONE sentinel — signals end of stream
broadcast.unsubscribe(queue)          # removes one subscriber
```

Each subscriber gets its own `RactorQueue`. `async_push` / `async_pop` cooperate with the Falcon fiber scheduler via `sleep(0)`.

---

## Server::BroadcastRegistry

Thread-safe `task_id → TaskBroadcast` map, held at the App class level and shared across all concurrent requests.

```ruby
registry = A2A::Server::BroadcastRegistry.new
registry.register(task_id, broadcast)   # called when a streaming task starts
registry.find(task_id)                  # => TaskBroadcast or nil
registry.unregister(task_id)            # called when the executor finishes
```

`tasks/resubscribe` and `tasks/cancel` use `registry.find` to locate the live broadcast for a running task.

---

## Server::PushConfigStore

In-memory store for push notification configurations, keyed by task ID. One instance is created per `Server::App` and exposed as `App.push_config_store`. You rarely interact with this directly — the four `tasks/pushNotification/*` handlers use it automatically.

```ruby
store = A2A::Server::PushConfigStore.new

store.set(task_id, config)   # => config — stores or replaces the config for this task
store.get(task_id)           # => PushNotificationConfig or nil
store.delete(task_id)        # => the deleted config or nil
store.list                   # => { task_id => config, … } snapshot
```

---

## Server::PushSender

Delivers webhook push notifications.

```ruby
sender = A2A::Server::PushSender.new(
  private_key: OpenSSL::PKey::RSA.generate(2048),  # for JWT signing
  key_id:      "my-key-id",
  issuer:      "my-agent"
)

sender.deliver(push_config, event)   # => true (success) or false (failure)
```

Schemes:

- `"bearer"` — signs a JWT with `RS256` and sends `Authorization: Bearer <token>`
- `"token"` — sends the static value as `Authorization: Token <value>` (or custom header)

---

## Server::App

The Roda-based Rack application. You don't instantiate this directly — `Server::Base` configures and freezes it.

**Routes:**

| Method | Path | Description |
|---|---|---|
| `GET` | `/agentCard` | Returns the AgentCard as JSON |
| `POST` | `/` | JSON-RPC 2.0 dispatch |
