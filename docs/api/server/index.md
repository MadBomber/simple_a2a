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
ctx.event_router  # => A2A::Server::EventRouter
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

## Server::EventRouter

Manages per-task SSE channels using `TypedBus`. You rarely interact with this directly — use `ctx.emit_status` and `ctx.emit_artifact` instead.

```ruby
router = A2A::Server::EventRouter.new
router.open(task_id)                     # creates a channel
router.publish(task_id, event)           # sends an event to subscribers
router.subscribe(task_id) { |event| … } # block receives raw event objects
router.close(task_id)                    # removes the channel
router.channel?(task_id)                 # => true/false
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
