# Streaming Demo

`examples/02_streaming` demonstrates `tasks/sendSubscribe` and Server-Sent Events (SSE). The server streams an article word by word, and the client prints chunks as they arrive.

## Files

| File | Purpose |
|---|---|
| `examples/02_streaming/server.rb` | Defines `StreamingExecutor`, advertises streaming support, and emits status and artifact events |
| `examples/02_streaming/client.rb` | Uses `A2A.sse_client` and `send_subscribe` to consume streamed events |

## Run it

From the repository root:

```bash
bundle exec ruby examples/run 02_streaming
```

Manual run:

```bash
bundle exec ruby examples/02_streaming/server.rb
bundle exec ruby examples/02_streaming/client.rb
```

## Server behavior

The streaming executor starts the task, emits a working status, sends artifact chunks, completes the task, and emits a final status.

```ruby
def call(ctx)
  ctx.task.start!
  ctx.emit_status

  WORDS.each_with_index do |word, i|
    text = i.zero? ? word : " #{word}"

    artifact = A2A::Models::Artifact.new(
      index: 0,
      parts: [A2A::Models::Part.text(text)],
      append: i > 0,
      last_chunk: i == WORDS.length - 1
    )

    ctx.emit_artifact(artifact, append: i > 0, last_chunk: i == WORDS.length - 1)
  end

  ctx.task.complete!
  ctx.emit_status(final: true)
end
```

The agent card declares streaming support:

```ruby
A2A::Models::AgentCapabilities.new(streaming: true)
```

## Client behavior

The client uses `A2A.sse_client` instead of `A2A.client`:

```ruby
client = A2A.sse_client(url: "http://localhost:9292")

client.send_subscribe(message: A2A::Models::Message.user("stream")) do |event|
  case event
  when A2A::Models::TaskStatusUpdateEvent
    # task state changed
  when A2A::Models::TaskArtifactUpdateEvent
    print event.artifact.parts.map(&:text).join
  end
end
```

It also tracks event count, word count, elapsed time, and effective words per minute, which makes it useful for checking end-to-end streaming behavior.

## Relationship to the guide

The [Streaming Responses guide](../guides/streaming.md) explains the API in isolation. This demo shows the same flow as a runnable pair of scripts.
