# simple_a2a

A Ruby gem implementing the [Agent2Agent (A2A) protocol](https://a2a-protocol.org/latest/) — an open standard by Google and the Linux Foundation for interoperability between AI agents.

This gem provides both an A2A client and server in a single package, built on the async Ruby ecosystem with Falcon as the recommended HTTP server.

## Protocol Reference

- **Official A2A Specification:** https://a2a-protocol.org/latest/
- **A2A Project on GitHub:** https://github.com/a2aproject/A2A

## Features

- Full A2A v1.0 protocol support (backward compatible with v0.3)
- JSON-RPC 2.0 over HTTP(S) — primary binding
- Server-Sent Events (SSE) for streaming responses
- Push notifications via webhooks (RS256 JWT)
- Task lifecycle management (submitted → working → completed/failed/canceled)
- AgentCard discovery endpoint
- Async-first via the `async` gem ecosystem (Falcon + async-http)
- Rack-compatible server with Roda routing
- Pipeline composition via `simple_flow`
- Per-task SSE fan-out via `typed_bus`

## Installation

Add to your Gemfile:

```ruby
gem "simple_a2a"
```

Or install directly:

```bash
gem install simple_a2a
```

## Usage

```ruby
require "simple_a2a"

# Define an agent executor
class MyExecutor < SimpleA2a::Server::AgentExecutor
  def call(context)
    context.task.start!
    context.task.complete!(
      artifacts: [
        SimpleA2a::Models::Artifact.new(
          parts: [SimpleA2a::Models::Part.text("Hello from my agent!")]
        )
      ]
    )
  end
end

# Build and run the server
card = SimpleA2a::Models::AgentCard.new(
  name:         "MyAgent",
  version:      "1.0",
  capabilities: SimpleA2a::Models::AgentCapabilities.new(streaming: true),
  skills:       [SimpleA2a::Models::AgentSkill.new(name: "greet")],
  interfaces:   [SimpleA2a::Models::AgentInterface.new(
    type: "json-rpc", url: "http://localhost:9292/a2a", version: "1.0"
  )]
)

server = SimpleA2a::Server::Base.new(agent_card: card, executor: MyExecutor.new)
server.run  # starts Falcon on port 9292
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run `rake test` to run the tests.

```bash
bin/setup
rake test
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/madbomber/simple_a2a.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
