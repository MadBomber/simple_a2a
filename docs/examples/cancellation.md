# 05 Cancellation

**Run it:**

```bash
bundle exec ruby examples/run 05_cancellation
```

**What it shows:** how to cancel an in-flight task mid-execution while other concurrent tasks run to completion.

---

## Files

| File | Purpose |
|---|---|
| `examples/05_cancellation/server.rb` | `SlowExecutor` that runs 10 one-second steps and checks `ctx.task.terminal?` between each step |
| `examples/05_cancellation/client.rb` | Starts three concurrent SSE subscriptions, cancels the middle task after 3 s, verifies final states |

---

## The scenario

Three tasks (A, B, C) start simultaneously via `tasks/sendSubscribe`. Each runs a 10-step loop with 1-second pauses — a 10-second total runtime without intervention. After 3 seconds the client calls `tasks/cancel` on Task B. Task B transitions to `canceled`; Tasks A and C run to completion unaffected.

This demonstrates three protocol guarantees:

1. **Mid-flight cancellation** — `tasks/cancel` interrupts a running task without touching sibling tasks.
2. **Cooperative cancellation** — the executor checks `ctx.task.terminal?` between steps and exits cleanly when cancelled.
3. **Terminal state isolation** — the `canceled` state is terminal; subsequent executor steps are skipped.

---

## Server — `SlowExecutor`

The executor emits one status event per step and checks for cancellation between steps:

```ruby
class SlowExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    ctx.task.start!
    ctx.emit_status

    10.times do |i|
      break if ctx.task.terminal?   # exit early if cancelled
      sleep 1
      ctx.emit_artifact(A2A::Models::Artifact.new(
        parts: [A2A::Models::Part.text("step #{i + 1}/10")]
      ))
    end

    return if ctx.task.terminal?
    ctx.task.complete!
    ctx.emit_status(final: true)
  end
end
```

The `AgentCapabilities` declares `streaming: true` so clients know to use `tasks/sendSubscribe`.

---

## Client — concurrent tasks with mid-flight cancel

Three SSE subscriptions run in separate threads. Each thread captures its task ID from the first status event:

```ruby
task_ids = {}
mutex    = Mutex.new

threads = %w[A B C].map do |label|
  Thread.new do
    A2A.sse_client(url: URL).send_subscribe(message: ...) do |event|
      if event.is_a?(A2A::Models::TaskStatusUpdateEvent)
        mutex.synchronize { task_ids[label] ||= event.task_id }
      end
    end
  end
end

sleep 3 until task_ids.key?("B")
client.cancel_task(task_ids["B"])
threads.each(&:join)
```

After all threads finish, the client calls `client.get_task` for each ID and asserts the expected states:

```
Task A: completed  ✓
Task B: canceled   ✓
Task C: completed  ✓
```

---

## Protocol coverage

| Spec section | What the demo shows |
|---|---|
| `tasks/cancel` | Client sends a cancel request by task ID while the task is mid-execution |
| `canceled` terminal state | Task B transitions to `canceled`; its SSE stream receives a final status event and closes |
| Concurrent task isolation | Tasks A and C are unaffected by the cancellation of task B |
| `AgentExecutor#cancel` | Default implementation calls `task.cancel!` and emits a final status event |
| `TaskState` lifecycle | `submitted → working → canceled` vs `submitted → working → completed` |
| Cooperative cancellation | Executor checks `ctx.task.terminal?` between steps and exits early when cancelled |
