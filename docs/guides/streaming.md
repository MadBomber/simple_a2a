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
        parts: [A2A::Models::Part.text(chunk)]
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

---

## Resubscribing to an existing task

`tasks/resubscribe` lets a client attach a new SSE stream to a task that is already running — useful when a connection drops and the client needs to reconnect without re-sending the original message.

```ruby
client = A2A.sse_client(url: "http://localhost:9292")

# The first event yielded is the current Task snapshot (a Hash, no `type` field).
# Subsequent events are the live stream from the executor.
client.resubscribe(task_id: "existing-task-id") do |event|
  case event
  when Hash
    puts "reconnected — current state: #{event['status']['state']}"
  when A2A::Models::TaskStatusUpdateEvent
    puts "[status] #{event.status.state}  final=#{event.final}"
  when A2A::Models::TaskArtifactUpdateEvent
    print event.artifact.parts.map(&:text).join
  end
end
```

`resubscribe` raises (server returns `UnsupportedOperationError`) if:
- The task ID does not exist (`TaskNotFoundError`)
- The task is already in a terminal state
- The task was not started with `tasks/sendSubscribe` (not in the broadcast registry)

Multiple clients may resubscribe to the same task concurrently — each gets an independent event queue backed by `RactorQueue`.

---

## AgentCard declaration

Advertise streaming support in your AgentCard:

```ruby
capabilities = A2A::Models::AgentCapabilities.new(streaming: true)
```

Clients can check `card.capabilities.streaming` before using `send_subscribe` or `resubscribe`.
