# Streaming Responses

`tasks/sendSubscribe` keeps the HTTP connection open and streams events as your executor progresses. This is ideal for long-running tasks where the client needs incremental feedback.

## Server side — emitting events

Use `ctx.emit_status` and `ctx.emit_artifact` inside your executor:

```ruby
class StreamingExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.start!
    ctx.emit_status   # publishes TaskStatusUpdateEvent(state: "working", final: false)

    # Stream artifact chunks
    ["Thinking… ", "Processing… ", "Done!"].each_with_index do |chunk, i|
      last = i == 2
      artifact = A2A::Models::Artifact.new(
        index:      0,
        parts:      [A2A::Models::Part.text(chunk)],
        append:     i > 0,   # true for chunks after the first
        last_chunk: last
      )
      ctx.emit_artifact(artifact, append: i > 0, last_chunk: last)
    end

    ctx.task.complete!
    ctx.emit_status(final: true)  # signals end of stream
  end
end
```

### Emit methods

| Method | Publishes | `final` |
|---|---|---|
| `ctx.emit_status` | `TaskStatusUpdateEvent` | pass `final: true` to close the stream |
| `ctx.emit_artifact(artifact, append:, last_chunk:)` | `TaskArtifactUpdateEvent` | always `false` |

Always emit `ctx.emit_status(final: true)` as your last event to close the SSE connection cleanly.

---

## Client side — consuming events

Use `Client::SSE#send_subscribe`:

```ruby
client = A2A.sse_client(url: "http://localhost:9292")

client.send_subscribe(message: A2A::Models::Message.user("go")) do |event|
  case event
  when A2A::Models::TaskStatusUpdateEvent
    puts "[status] #{event.status.state}  final=#{event.final}"
    break if event.final
  when A2A::Models::TaskArtifactUpdateEvent
    print event.artifact.parts.map(&:text).join
    $stdout.flush
  end
end
```

The block is called for each parsed SSE event. Unrecognized event types yield a plain `Hash`.

---

## AgentCard declaration

Advertise streaming support in your AgentCard:

```ruby
capabilities = A2A::Models::AgentCapabilities.new(streaming: true)
```

Clients can check `card.capabilities.streaming` before using `send_subscribe`.
