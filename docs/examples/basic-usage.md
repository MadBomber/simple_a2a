# Basic Usage Demo

`examples/01_basic_usage` is the smallest complete client/server demo. It shows the non-streaming JSON-RPC flow for an A2A agent.

## Files

| File | Purpose |
|---|---|
| `examples/01_basic_usage/server.rb` | Defines `BasicExecutor`, builds the `BasicAgent` card, and starts the A2A server |
| `examples/01_basic_usage/client.rb` | Discovers the agent, sends tasks, lists tasks, retrieves a task, and handles an expected error |

## Run it

From the repository root:

```bash
bundle exec ruby examples/run 01_basic_usage
```

The launcher starts the server on `http://localhost:9292`, runs the client, and stops the server afterward.

Manual run:

```bash
bundle exec ruby examples/01_basic_usage/server.rb
bundle exec ruby examples/01_basic_usage/client.rb
```

## Server behavior

`BasicExecutor` subclasses `A2A::Server::AgentExecutor` and implements `#call(ctx)`. It reads the incoming user message with `ctx.message.text_content`, prepends a random greeting, and completes the task with one text artifact.

```ruby
class BasicExecutor < A2A::Server::AgentExecutor
  GREETINGS = %w[Hello Greetings Salutations Hey Howdy].freeze

  def call(ctx)
    input = ctx.message.text_content.strip
    reply = "#{GREETINGS.sample}: #{input}"

    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name: "reply",
        parts: [A2A::Models::Part.text(reply)]
      )
    ])
  end
end
```

The server advertises one skill named `greet` and one JSON-RPC interface at `http://localhost:9292`.

## Client flow

The client demonstrates the core client API:

```ruby
client = A2A.client(url: "http://localhost:9292")

card = client.agent_card
task = client.send_task(message: A2A::Models::Message.user("world"))
tasks = client.list_tasks
retrieved = client.get_task(task.id)
```

It also calls `client.get_task("no-such-task-id")` and rescues `A2A::Error`, which is a compact example of handling protocol or server errors from a client.

## What to study next

Use this demo when learning the minimal server shape:

| Concept | Where to look |
|---|---|
| Executor contract | `BasicExecutor#call` in `server.rb` |
| Agent discovery | `client.agent_card` in `client.rb` |
| Task submission | `client.send_task` in `client.rb` |
| Storage-backed task lookup | `client.list_tasks` and `client.get_task` |
