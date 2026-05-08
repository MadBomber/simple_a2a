# Example: Echo Agent

A complete, runnable example of a simple echo agent and a client that talks to it.

## Server (`echo_server.rb`)

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

card = A2A::Models::AgentCard.new(
  name:         "EchoAgent",
  version:      "1.0",
  description:  "Echoes every message back",
  capabilities: A2A::Models::AgentCapabilities.new,
  skills:       [A2A::Models::AgentSkill.new(name: "echo", description: "Echoes input")],
  interfaces:   [A2A::Models::AgentInterface.new(
    type: "json-rpc", url: "http://localhost:9292", version: "1.0"
  )]
)

A2A.server(agent_card: card, executor: EchoExecutor.new).run
```

```bash
ruby echo_server.rb
# Falcon listening on http://localhost:9292
```

## Client (`echo_client.rb`)

```ruby
require "simple_a2a"

client = A2A.client(url: "http://localhost:9292")

# Discover the agent
card = client.agent_card
puts "Connected to: #{card.name} v#{card.version}"

# Send a task
task = client.send_task(message: A2A::Models::Message.user("hello world"))
puts "State:  #{task.status.state}"
puts "Reply:  #{task.artifacts.first.parts.first.text}"
# => "Echo: hello world"

# List all tasks
tasks = client.list_tasks
puts "Total tasks: #{tasks.size}"
```

## Streaming variant

For agents that stream incremental output, see the [Streaming guide](../guides/streaming.md).
