# 06 Push Notifications

**Run it:**

```bash
bundle exec ruby examples/run 06_push_notifications
```

**What it shows:** the full push notification CRUD cycle — registering a webhook, confirming it, receiving out-of-band task events, then deleting the config.

---

## Files

| File | Purpose |
|---|---|
| `examples/06_push_notifications/server.rb` | `PushExecutor` that delivers `TaskStatusUpdateEvent` payloads to the registered webhook after each step |
| `examples/06_push_notifications/client.rb` | Runs a local WEBrick webhook receiver on port 9293, submits a task, and exercises all four push-notification RPC methods |

---

## The scenario

The client holds no persistent SSE connection. Instead:

1. It starts a local HTTP receiver on port 9293 backed by a `Queue`.
2. It submits a task via `tasks/send` (synchronous — gets back the initial task object).
3. It registers the webhook URL via `tasks/pushNotification/set`.
4. The server `PushExecutor` runs its work steps; after each step it looks up the push config and delivers a `TaskStatusUpdateEvent` to the webhook.
5. The client's `Queue` collects payloads; the main thread waits until it receives the final `completed` event.
6. The client confirms the config exists (`tasks/pushNotification/get`), lists all configs (`tasks/pushNotification/list`), then removes the config (`tasks/pushNotification/delete`).

---

## Server design

`PushExecutor` is initialized with a shared `PushSender` and `PushConfigStore`. After each work step it delivers an event:

```ruby
class PushExecutor < A2A::Server::AgentExecutor
  def initialize(push_sender:, push_config_store:)
    @push_sender       = push_sender
    @push_config_store = push_config_store
  end

  def call(ctx)
    ctx.task.start!
    deliver(ctx)

    3.times do |i|
      sleep 1
      ctx.emit_artifact(...)
      deliver(ctx)
    end

    ctx.task.complete!
    deliver(ctx)
  end

  private

  def deliver(ctx)
    config = @push_config_store.get(ctx.task.id)
    return unless config
    event = A2A::Models::TaskStatusUpdateEvent.new(
      task_id: ctx.task.id, status: ctx.task.status, final: ctx.task.terminal?
    )
    @push_sender.deliver(config, event)
  end
end
```

The same `push_config_store` instance is passed to both the executor and `A2A.server(push_config_store:)`, so the server's built-in RPC handlers and the executor share one store.

---

## Client design

WEBrick in a background thread writes received payloads into a `Queue`; the main thread reads from it:

```ruby
queue = Queue.new

server = WEBrick::HTTPServer.new(Port: 9293, Logger: ..., AccessLog: [])
server.mount_proc("/webhook") do |req, res|
  queue.push(JSON.parse(req.body))
  res.status = 200
end
Thread.new { server.start }

# Register the webhook
client.rpc_call("tasks/pushNotification/set", {
  "id"     => task.id,
  "config" => { "webhookUrl" => "http://localhost:9293/webhook" }
})

# Wait for the final push
loop do
  payload = queue.pop
  break if payload.dig("status", "state") == "completed"
end
```

---

## Protocol coverage

| Spec section | What the demo shows |
|---|---|
| `tasks/pushNotification/set` | Client registers a `PushNotificationConfig` containing a webhook URL |
| `tasks/pushNotification/get` | Client confirms the config is stored by retrieving it by task ID |
| `tasks/pushNotification/list` | Client lists all registered push configs on the server |
| `tasks/pushNotification/delete` | Client removes the config; list confirms zero configs remain |
| `PushNotificationConfig` model | `webhookUrl` and optional `authenticationInfo` fields |
| `PushSender` | Server delivers `TaskStatusUpdateEvent` payloads as HTTP POSTs to the webhook URL |
| `AgentCapabilities.push_notifications` | `true` in the agent card; server rejects push RPC calls if `false` |
| Out-of-band delivery | Client receives progress updates without maintaining any persistent connection |
