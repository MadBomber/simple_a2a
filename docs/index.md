# simple_a2a

A Ruby gem implementing the [Agent2Agent (A2A) protocol](https://a2a-protocol.org/latest/) — an open standard by Google and the Linux Foundation for interoperability between AI agents.

`simple_a2a` provides a complete A2A client and server in a single package, built on the async Ruby ecosystem with [Falcon](https://github.com/socketry/falcon) as the recommended HTTP server.

---

## What is A2A?

The Agent2Agent (A2A) protocol defines how AI agents running on different platforms, frameworks, and vendors can discover each other, exchange tasks, and stream results — without vendor lock-in.

- Agents expose a JSON-RPC 2.0 over HTTP endpoint
- Clients send tasks and receive structured results
- Streaming uses Server-Sent Events (SSE)
- Push notifications use webhooks (RS256 JWT)
- AgentCards describe capabilities and skills

**Protocol Reference:** [https://a2a-protocol.org/latest/](https://a2a-protocol.org/latest/)

---

## At a Glance

```ruby
require "simple_a2a"

# 1. Implement your agent logic
class MyExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    input = ctx.message.text_content
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        parts: [A2A::Models::Part.text("You said: #{input}")]
      )
    ])
  end
end

# 2. Describe your agent
card = A2A::Models::AgentCard.new(
  name:         "MyAgent",
  version:      "1.0",
  capabilities: A2A::Models::AgentCapabilities.new,
  skills:       [A2A::Models::AgentSkill.new(name: "reply")],
  interfaces:   [A2A::Models::AgentInterface.new(
    type: "json-rpc", url: "http://localhost:9292", version: "1.0"
  )]
)

# 3. Start the server
A2A.server(agent_card: card, executor: MyExecutor.new).run
```

```ruby
# Client — send a task to any A2A agent
client = A2A.client(url: "http://localhost:9292")
task   = client.send_task(message: A2A::Models::Message.user("hello"))
puts task.status.state   # => "completed"
```

---

## Features

| Feature | Details |
|---|---|
| Protocol | A2A v1.0, backward compatible with v0.3 |
| Transport | JSON-RPC 2.0 over HTTP(S) |
| Streaming | Server-Sent Events (SSE) |
| Push notifications | Webhooks with RS256 JWT signing |
| Task lifecycle | `submitted → working → completed/failed/canceled` |
| Discovery | AgentCard endpoint at `GET /agentCard` |
| Async runtime | `async` gem ecosystem — non-blocking I/O |
| HTTP server | Falcon (recommended), any Rack-compatible server |
| HTTP client | `async-http` (`Async::HTTP::Internet`) |
| Storage | In-memory (thread-safe); pluggable via `Storage::Base` |
| Routing | Roda with JSON-RPC dispatch |
| Autoloading | Zeitwerk |

## Runnable demos

The repository includes three demo applications under `examples/`:

| Demo | Shows |
|---|---|
| `01_basic_usage` | Agent discovery, `tasks/send`, task listing, task lookup, and error handling |
| `02_streaming` | `tasks/sendSubscribe` with Server-Sent Events and incremental artifact chunks |
| `03_llm_research` | Multi-agent routing, parallel streaming LLM calls, evaluator agent, and a Sinatra web client |

Run the basic and streaming demos end-to-end with:

```bash
bundle exec ruby examples/run 01_basic_usage
bundle exec ruby examples/run 02_streaming
```

The LLM research demo requires `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and its demo-specific gems. See the [examples overview](examples/index.md) for setup details.
