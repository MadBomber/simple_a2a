# Quick Start

This guide walks through building a minimal echo agent and a client that talks to it.

## 1. Create the executor

An **executor** contains your agent's logic. Subclass `A2A::Server::AgentExecutor` and implement `#call`:

```ruby
require "simple_a2a"

class EchoExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    input = ctx.message.text_content
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "reply",
        parts: [A2A::Models::Part.text("Echo: #{input}")]
      )
    ])
  end
end
```

`ctx` is an `A2A::Server::Context` that gives you access to the incoming message, the task object, and helpers for emitting streaming events.

## 2. Build the agent card

The **AgentCard** describes your agent to clients:

```ruby
card = A2A::Models::AgentCard.new(
  name:         "EchoAgent",
  version:      "1.0",
  capabilities: A2A::Models::AgentCapabilities.new,
  skills:       [A2A::Models::AgentSkill.new(name: "echo", description: "Echoes your input")],
  interfaces:   [A2A::Models::AgentInterface.new(
    type:    "json-rpc",
    url:     "http://localhost:9292",
    version: "1.0"
  )]
)
```

## 3. Start the server

```ruby
server = A2A.server(agent_card: card, executor: EchoExecutor.new)
server.run   # starts Falcon on localhost:9292
```

Or with custom host/port:

```ruby
server = A2A::Server::Base.new(
  agent_card: card,
  executor:   EchoExecutor.new,
  host:       "0.0.0.0",
  port:       8080
)
server.run
```

## 4. Send a task from a client

In a separate process or script:

```ruby
require "simple_a2a"

client = A2A.client(url: "http://localhost:9292")

task = client.send_task(message: A2A::Models::Message.user("hello there"))
puts task.status.state                               # => "completed"
puts task.artifacts.first.parts.first.text           # => "Echo: hello there"
```

## 5. Discover the agent card

```ruby
card = client.agent_card
puts card.name      # => "EchoAgent"
puts card.version   # => "1.0"
```

## 6. List and retrieve tasks

```ruby
tasks   = client.list_tasks
task    = client.get_task(tasks.first.id)
puts task.id
```

## Next steps

- [Architecture overview](../architecture/index.md) — understand the components
- [Streaming responses](../guides/streaming.md) — emit incremental SSE events
- [Runnable examples](../examples/index.md) - run the demo apps in `examples/`
- [Push notifications](../guides/push-notifications.md) — webhook delivery
- [API reference](../api/index.md) — full class and method docs
