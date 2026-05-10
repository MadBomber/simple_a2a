# 07 Agent Chaining

**Run it:**

```bash
bundle exec ruby examples/run 07_agent_chaining
```

**What it shows:** one agent calling peer agents using `A2A.client` inside its executor — the same client interface an external caller would use.

---

## Files

| File | Purpose |
|---|---|
| `examples/07_agent_chaining/server.rb` | Three agents at `/reverse`, `/shout`, `/pipeline`; `PipelineExecutor` chains the other two |
| `examples/07_agent_chaining/client.rb` | External client that speaks only to `/pipeline`; the internal delegation is invisible to it |

---

## The scenario

The demo mounts three agents on one server:

| Path | Agent | What it does |
|---|---|---|
| `/reverse` | `ReverseAgent` | Returns the input string with characters reversed |
| `/shout` | `ShoutAgent` | Returns the input string uppercased with `!!!` appended |
| `/pipeline` | `PipelineAgent` | Calls `/reverse` then `/shout` internally and returns the final result |

The external client sends one message to `/pipeline`. The pipeline executor calls the other two agents in sequence using `A2A.client` and returns their combined output. The external client never learns that two additional A2A calls were made internally.

---

## Server — `PipelineExecutor`

The executor holds pre-built `A2A.client` instances pointing to its peer agents:

```ruby
class PipelineExecutor < A2A::Server::AgentExecutor
  def initialize(reverse_url:, shout_url:)
    @reverse_client = A2A.client(url: reverse_url)
    @shout_client   = A2A.client(url: shout_url)
  end

  def call(ctx)
    input = ctx.message.text_content.strip

    reversed = @reverse_client
      .send_task(message: A2A::Models::Message.user(input))
      .artifacts.first&.parts&.first&.text

    shouted = @shout_client
      .send_task(message: A2A::Models::Message.user(reversed))
      .artifacts.first&.parts&.first&.text

    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "result",
        parts: [A2A::Models::Part.text(shouted)]
      )
    ])
  end
end
```

All three agents are mounted on one port via `A2A.multi_server`:

```ruby
A2A.multi_server(
  agents: {
    "/reverse"  => { agent_card: reverse_card,  executor: ReverseExecutor.new },
    "/shout"    => { agent_card: shout_card,     executor: ShoutExecutor.new },
    "/pipeline" => { agent_card: pipeline_card,  executor: pipeline_executor }
  },
  port: 9292
).run
```

---

## Client flow

The external client discovers all three agent cards then calls the pipeline:

```ruby
client = A2A.client(url: "http://localhost:9292/pipeline")
task   = client.send_task(message: A2A::Models::Message.user("hello world"))
puts task.artifacts.first.parts.first.text
# => "DLROW OLLEH!!!"
```

The client also fetches agent cards from all three paths to show they are independently discoverable.

---

## Protocol coverage

| Spec section | What the demo shows |
|---|---|
| Agent-to-agent delegation | An executor uses `A2A.client` to call peer agents during task execution |
| `A2A.multi_server` | Three agents hosted at `/reverse`, `/shout`, `/pipeline` on one port |
| Agent Card discovery | Client discovers all three cards; pipeline card describes its composed capability |
| `tasks/send` | Sub-agents called synchronously within the pipeline executor's fiber |
| Protocol transparency | Internal A2A calls use the same JSON-RPC wire format as external calls |
| Composability | Any agent can act as both a server (to its caller) and a client (to its dependencies) |
