# simple_a2a

<div class="grid" markdown>

<div markdown>

![simple_a2a](assets/images/simple_a2a.jpg){ width="100%" }

<p align="center"><em>"Anyone speak robot?"</em></p>

</div>

<div markdown>

**A Ruby gem implementing the [Agent2Agent (A2A) protocol](https://a2a-protocol.org/latest/)**

A complete A2A client and server in a single package, built on the async Ruby ecosystem with Falcon as the recommended HTTP server.

- Full A2A v1.0 protocol, backward compatible with v0.3
- JSON-RPC 2.0 over HTTP(S)
- Server-Sent Events (SSE) streaming
- Push notifications via webhooks (RS256 JWT)
- Task lifecycle: `submitted → working → completed/failed/canceled`
- AgentCard discovery at `GET /agentCard`
- Multi-agent hosting via `A2A.multi_server`
- `async` gem ecosystem — non-blocking I/O
- Falcon HTTP server; any Rack-compatible server
- In-memory storage; pluggable via `Storage::Base`
- Roda routing, Zeitwerk autoloading
- [:material-book-open: Full documentation](https://madbomber.github.io/simple_a2a)

</div>

</div>

<p align="center" markdown>
[:material-book-open: Documentation](https://madbomber.github.io/simple_a2a){ .md-button .md-button--primary }
[:material-github: GitHub](https://github.com/MadBomber/simple_a2a){ .md-button }
</p>

---

## MCP vs. A2A

Two open protocols address different dimensions of AI agent integration — and they are designed to complement each other.

### MCP — Vertical Integration (Agent ↕ Environment)

The [Model Context Protocol](https://modelcontextprotocol.io/) (MCP), introduced by Anthropic in November 2024, defines how an AI agent connects to the tools, data sources, and services in its environment — file systems, databases, APIs, browsers, and code execution engines. MCP uses a client-server model where the agent is the client and each external capability is a server. This is *vertical* integration: the agent reaches downward into its local context and outward into external services through a uniform interface.

### A2A — Horizontal Integration (Agent ↔ Agent)

The [Agent2Agent Protocol](https://a2a-protocol.org/latest/) (A2A), introduced by Google in April 2025 and donated to the Linux Foundation for vendor-neutral governance, defines how autonomous agents running on different platforms, frameworks, and vendors can discover one another, delegate tasks, and stream results in real time. This is *horizontal* integration: peer agents — each with its own specialization, runtime, and vendor — collaborate as equals across organizational and technology boundaries.

### Together

MCP and A2A are complementary. A single agent can use MCP to access its tools and A2A to delegate subtasks to peer agents. `simple_a2a` implements the A2A layer.

### References

- Anthropic: [Introducing the Model Context Protocol](https://www.anthropic.com/news/model-context-protocol) (November 2024)
- Google Developers Blog: [A2A: A new era of agent interoperability](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/) (April 2025)
- Linux Foundation: [Launch of the Agent2Agent Protocol Project](https://www.linuxfoundation.org/press/linux-foundation-launches-the-agent2agent-protocol-project-to-enable-secure-intelligent-communication-between-ai-agents)
- A2A Project on GitHub: [https://github.com/a2aproject/A2A](https://github.com/a2aproject/A2A)

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
