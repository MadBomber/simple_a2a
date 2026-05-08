# simple_a2a

A Ruby gem implementing the [Agent2Agent (A2A) protocol](https://a2a-protocol.org/latest/) — an open standard by Google and the Linux Foundation for interoperability between AI agents.

`simple_a2a` provides a complete A2A client and server in a single package, built on the async Ruby ecosystem with [Falcon](https://github.com/socketry/falcon) as the recommended HTTP server.

**Documentation:** [https://madbomber.github.io/simple_a2a](https://madbomber.github.io/simple_a2a)

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

## Development

```bash
bin/setup       # install dependencies
bundle exec rake test   # run the test suite (222 tests)
```

## Contributing

Bug reports and pull requests are welcome at [https://github.com/MadBomber/simple_a2a](https://github.com/MadBomber/simple_a2a).

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
