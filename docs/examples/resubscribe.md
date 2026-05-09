# 04 Resubscribe

**Run it:**

```bash
bundle exec ruby examples/run 04_resubscribe
```

**What it shows:** two independent SSE subscribers watching the same running task — one started with `tasks/sendSubscribe`, the other attached mid-stream with `tasks/resubscribe`.

---

## The scenario

A five-step analysis pipeline runs for ~6 seconds. Subscriber 1 starts the task and begins receiving events immediately. As soon as it has the task ID, Subscriber 2 calls `tasks/resubscribe`. Subscriber 2's **first event is the current Task snapshot** — the live state of the task at the moment it joined — and it then receives all remaining events just like Subscriber 1.

This demonstrates three protocol guarantees from the A2A specification:

1. **Snapshot on join** — `tasks/resubscribe` always delivers the current Task object as its first SSE event, so late-joining clients never miss the task's current state.
2. **Independent fan-out** — each subscriber has its own event queue; one slow or disconnecting subscriber does not affect the other.
3. **Single completion** — the task completes once; both streams close cleanly when the executor emits its final status event.

---

## Expected output

```
=== Agent Card ===
  Name:        AnalysisAgent
  Description: Multi-step analysis pipeline — demonstrates tasks/resubscribe
  Streaming:   true

[subscriber-1] tasks/sendSubscribe (new task)       [subscriber-2] tasks/resubscribe (join mid-stream)
────────────────────────────────────────────────────────────────────────────────────
[subscriber-1] status: working
[subscriber-2] (resubscribing to task c29189f8…)
[subscriber-2] (snapshot) state=working, steps so far: 0
[subscriber-1] Step 1/5: Collecting data from sources
[subscriber-2] Step 1/5: Collecting data from sources
[subscriber-1] Step 2/5: Filtering and normalising records
[subscriber-2] Step 2/5: Filtering and normalising records
...
[subscriber-1] status (final): completed
[subscriber-2] status (final): completed

=== Summary ===
  Subscriber 1 — events received : 7
  Subscriber 1 — artifact steps  : 5

  Subscriber 2 — events received : 7
  Subscriber 2 — task snapshot   : yes
  Subscriber 2 — artifact steps  : 5
  Subscriber 2 — joined at step  : 1 of 5

  Both streams terminated cleanly: true
```

---

## How it works

### Server — `AnalysisExecutor`

A straightforward streaming executor. Emits one `TaskArtifactUpdateEvent` per step with a 1.2-second pause between steps, giving the client time to resubscribe mid-stream.

```ruby
class AnalysisExecutor < A2A::Server::AgentExecutor
  STEPS = [
    "Collecting data from sources",
    "Filtering and normalising records",
    "Running statistical analysis",
    "Detecting anomalies",
    "Generating final report"
  ].freeze

  def call(ctx)
    ctx.task.start!
    ctx.emit_status

    STEPS.each_with_index do |description, i|
      sleep 1.2
      ctx.emit_artifact(A2A::Models::Artifact.new(
        index:      i,
        parts:      [A2A::Models::Part.text("Step #{i + 1}/#{STEPS.length}: #{description}")],
        last_chunk: true
      ), last_chunk: true)
    end

    ctx.task.complete!
    ctx.emit_status(final: true)
  end
end
```

### Client — concurrent subscribers via `Async`

Both subscribers run inside a single `Async` reactor. Subscriber 1 runs in a background async task so it doesn't block; once it captures the task ID from the first status event, the main fiber calls `resubscribe` synchronously.

```ruby
Async do |reactor|
  captured_task_id = nil

  # Subscriber 1 — starts the task
  sub1_task = reactor.async do
    A2A.sse_client(url: URL).send_subscribe(message: msg) do |event|
      captured_task_id ||= event.task_id if event.respond_to?(:task_id)
      # … print event …
    end
  end

  # Wait for the task ID, then attach Subscriber 2
  loop { break if captured_task_id; reactor.sleep(0.05) }

  A2A.sse_client(url: URL).resubscribe(task_id: captured_task_id) do |event|
    case event
    when Hash                                    # Task snapshot — first event only
      puts "(snapshot) state=#{event.dig('status', 'state')}"
    when A2A::Models::TaskStatusUpdateEvent, A2A::Models::TaskArtifactUpdateEvent
      # … print event …
    end
  end

  sub1_task.wait
end
```

### Under the hood — `TaskBroadcast`

When `handle_send_subscribe` creates the task, it also creates a `TaskBroadcast` and registers it in the `BroadcastRegistry` under the task ID. Each SSE subscriber — whether the original or a resubscriber — gets its own `RactorQueue` from `broadcast.subscribe`. The executor calls `ctx.emit_status` and `ctx.emit_artifact`, which call `broadcast.publish`, which calls `async_push` on every subscriber queue. A pump loop in each SSE handler calls `async_pop` and writes SSE frames to the HTTP body. When the executor finishes, `broadcast.close` pushes the `DONE` sentinel to all queues and the pump loops exit cleanly.
