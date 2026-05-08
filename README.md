# simple_a2a

A Ruby gem implementing the [Agent2Agent (A2A) protocol](https://a2a-protocol.org/latest/) — an open standard by Google and the Linux Foundation for interoperability between AI agents.

`simple_a2a` provides a complete A2A client and server in a single package, built on the async Ruby ecosystem with [Falcon](https://github.com/socketry/falcon) as the recommended HTTP server.

## Documentation

The full documentation website is available at [https://madbomber.github.io/simple_a2a](https://madbomber.github.io/simple_a2a).

## Lineage

`simple_a2a` is the successor to my earlier Ruby gem, `simple_acp`. That gem implemented the Agent Communication Protocol (ACP), which IBM Research introduced through the BeeAI project for interoperable agent communication. ACP later merged into A2A under the Linux Foundation, with the ACP team contributing its technology and expertise to the A2A effort.

A2A itself was created by Google and then donated to the Linux Foundation for neutral, open governance. The current A2A specification is maintained by the Linux Foundation-hosted [Agent2Agent project](https://github.com/a2aproject/A2A) and published at [a2a-protocol.org](https://a2a-protocol.org/latest/).

> My opinion: the A2A specification is still a little jagged in places. A simple example is that it does not clearly cover whether an A2A server is expected to host only one agent or may host multiple agents. That is a minor example, but it points to the kind of operational detail the specification still needs to tighten up.

References:

- IBM Research: [Agent Communication Protocol](https://research.ibm.com/projects/agent-communication-protocol)
- BeeAI announcement: [ACP Joins Forces with A2A Under the Linux Foundation](https://github.com/orgs/i-am-bee/discussions/5)
- Linux Foundation: [Launch of the Agent2Agent Protocol Project](https://www.linuxfoundation.org/press/linux-foundation-launches-the-agent2agent-protocol-project-to-enable-secure-intelligent-communication-between-ai-agents)

## Protocol Reference

- **Official A2A Specification:** [https://a2a-protocol.org/latest/](https://a2a-protocol.org/latest/)
- **A2A Project on GitHub:** [https://github.com/a2aproject/A2A](https://github.com/a2aproject/A2A)

## Features

- Full A2A v1.0 protocol support (backward compatible with v0.3)
- JSON-RPC 2.0 over HTTP(S) — primary binding
- Server-Sent Events (SSE) for streaming responses
- Push notifications via webhooks (RS256 JWT)
- Task lifecycle management (`submitted → working → completed/failed/canceled`)
- AgentCard discovery endpoint at `GET /agentCard`
- Multi-agent hosting with path-based routing via `A2A.multi_server`
- Async-first via the `async` gem ecosystem (Falcon + async-http)
- Rack-compatible server with Roda routing
- Zeitwerk autoloading — top-level module is `A2A`

## Installation

Add to your Gemfile:

```ruby
gem "simple_a2a"
```

Or install directly:

```bash
gem install simple_a2a
```

## Quick start

```ruby
require "simple_a2a"

# Define your agent logic
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

# Describe your agent
card = A2A::Models::AgentCard.new(
  name:         "MyAgent",
  version:      "1.0",
  capabilities: A2A::Models::AgentCapabilities.new,
  skills:       [A2A::Models::AgentSkill.new(name: "reply")],
  interfaces:   [A2A::Models::AgentInterface.new(
    type: "json-rpc", url: "http://localhost:9292", version: "1.0"
  )]
)

# Start the server (blocks — runs Falcon on port 9292)
A2A.server(agent_card: card, executor: MyExecutor.new).run
```

```ruby
# Client — talk to any A2A agent
client = A2A.client(url: "http://localhost:9292")

task = client.send_task(message: A2A::Models::Message.user("hello"))
puts task.status.state                       # => "completed"
puts task.artifacts.first.parts.first.text   # => "You said: hello"
```

## Task lifecycle

```
submitted → working → completed   (terminal)
                    → failed      (terminal)
                    → canceled    (terminal)
                    → rejected    (terminal)
                    → input_required  (interrupted)
                    → auth_required   (interrupted)
```

Terminal tasks cannot be canceled. Interrupted tasks can be resumed by sending a new message.

## Streaming

```ruby
# Server — emit incremental events
class StreamingExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.start!
    ctx.emit_status

    ctx.emit_artifact(A2A::Models::Artifact.new(
      parts: [A2A::Models::Part.text("thinking… ")]
    ))

    ctx.task.complete!
    ctx.emit_status(final: true)
  end
end
```

```ruby
# Client — consume SSE events
client = A2A.sse_client(url: "http://localhost:9292")

client.send_subscribe(message: A2A::Models::Message.user("go")) do |event|
  case event
  when A2A::Models::TaskStatusUpdateEvent
    puts "status: #{event.status.state}"
  when A2A::Models::TaskArtifactUpdateEvent
    print event.artifact.parts.map(&:text).join
  end
end
```

## Multi-agent server

Use `A2A.multi_server` to host multiple A2A agents in one Falcon process, with each agent mounted at its own path:

```ruby
A2A.multi_server(
  agents: {
    "/research"  => { agent_card: research_card,  executor: ResearchExecutor.new },
    "/evaluator" => { agent_card: evaluator_card, executor: EvaluatorExecutor.new }
  },
  port: 9292
).run
```

Each mounted agent has its own AgentCard, executor, storage, and event router.

## Examples

The repository includes three runnable demo apps:

| Demo | Shows |
|---|---|
| `01_basic_usage` | Agent discovery, `tasks/send`, task listing, task lookup, and error handling |
| `02_streaming` | `tasks/sendSubscribe` with Server-Sent Events and incremental artifact chunks |
| `03_llm_research` | Multi-agent routing, parallel streaming LLM calls, evaluator agent, and a Sinatra web client |

Run the basic and streaming demos end-to-end:

```bash
bundle exec ruby examples/run 01_basic_usage
bundle exec ruby examples/run 02_streaming
```

The LLM research demo requires `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and demo-specific gems. See the full documentation for setup details.

## Development

```bash
bin/setup             # install dependencies
bundle exec rake test # run the test suite
```

## Contributing

Bug reports and pull requests are welcome at [https://github.com/MadBomber/simple_a2a](https://github.com/MadBomber/simple_a2a).

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
