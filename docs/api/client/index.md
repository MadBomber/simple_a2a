# Client API

## Client::Base

Synchronous JSON-RPC client backed by `async/http`. Works inside or outside an async reactor.

```ruby
client = A2A.client(url: "http://localhost:9292")
# or
client = A2A::Client::Base.new(
  url:     "http://localhost:9292",
  headers: { "Authorization" => "Bearer token" }
)
```

### Methods

#### `#agent_card` → `A2A::Models::AgentCard`

Fetches and parses the AgentCard from `GET /agentCard`.

```ruby
card = client.agent_card
puts card.name
puts card.capabilities.streaming
```

#### `#send_task(message:, **opts)` → `A2A::Models::Task`

Sends a `tasks/send` request and waits for the completed task.

```ruby
task = client.send_task(
  message:    A2A::Models::Message.user("hello"),
  task_id:    "my-task-id",    # optional — server assigns if omitted
  context_id: "ctx-1",         # optional
  metadata:   { source: "web" } # optional
)
puts task.status.state   # => "completed"
```

#### `#get_task(task_id)` → `A2A::Models::Task`

Retrieves a task by ID (`tasks/get`). Raises `A2A::Error` if not found.

```ruby
task = client.get_task("abc-123")
```

#### `#list_tasks` → `[A2A::Models::Task]`

Returns all tasks from the server (`tasks/list`).

```ruby
tasks = client.list_tasks
tasks.each { |t| puts "#{t.id}: #{t.status.state}" }
```

#### `#cancel_task(task_id)` → `A2A::Models::Task`

Cancels a non-terminal task (`tasks/cancel`). Raises `A2A::Error` if not cancelable.

```ruby
task = client.cancel_task("abc-123")
puts task.status.state  # => "canceled"
```

### Error handling

All RPC errors raise `A2A::Error` with the server's error message:

```ruby
begin
  client.get_task("no-such-id")
rescue A2A::Error => e
  puts e.message   # => "Task no-such-id not found"
end
```

---

## Client::SSE

Extends `Client::Base` with streaming support via `tasks/sendSubscribe`.

```ruby
client = A2A.sse_client(url: "http://localhost:9292")
# or
client = A2A::Client::SSE.new(url: "http://localhost:9292")
```

### `#send_subscribe(message:, **opts, &block)`

Opens an SSE connection and yields events as they arrive. Blocks until the stream closes.

```ruby
client.send_subscribe(message: A2A::Models::Message.user("process this")) do |event|
  case event
  when A2A::Models::TaskStatusUpdateEvent
    puts "Status: #{event.status.state} (final=#{event.final})"
  when A2A::Models::TaskArtifactUpdateEvent
    puts "Artifact chunk: #{event.artifact.parts.map(&:text).join}"
  end
end
```

Events are instances of:
- `A2A::Models::TaskStatusUpdateEvent`
- `A2A::Models::TaskArtifactUpdateEvent`
- `Hash` — for unrecognized event types

The stream ends when the server sends a `final: true` event. The block is not called for malformed or comment-only SSE frames.

### `#resubscribe(task_id:, &block)`

Attaches an SSE stream to an already-running task. The first event yielded to the block is the current Task snapshot (a plain `Hash` — no `type` field); subsequent events are the live stream.

```ruby
client.resubscribe(task_id: "existing-task-id") do |event|
  case event
  when Hash
    puts "reconnected — state: #{event['status']['state']}"
  when A2A::Models::TaskStatusUpdateEvent
    puts "Status: #{event.status.state} (final=#{event.final})"
  when A2A::Models::TaskArtifactUpdateEvent
    puts "Artifact: #{event.artifact.parts.map(&:text).join}"
  end
end
```

Returns `UnsupportedOperationError` (via `A2A::Error`) if the task is terminal or not currently streaming.

### Using inside an Async reactor

Both `Base` and `SSE` detect whether they're already inside an `Async` reactor via `Async::Task.current?`. Inside a reactor, they call the underlying `Async::HTTP::Internet` directly. Outside, they wrap the call in `Async { }.wait`.

```ruby
Async do
  client = A2A.client(url: "http://localhost:9292")
  task   = client.send_task(message: A2A::Models::Message.user("hi"))
  puts task.id
end
```
