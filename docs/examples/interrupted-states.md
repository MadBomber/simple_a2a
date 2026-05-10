# 08 Interrupted States

**Run it:**

```bash
bundle exec ruby examples/run 08_interrupted_states
```

**What it shows:** `input_required` and `auth_required` — the two interrupted task states — with multi-turn conversations threaded by `message.context_id`.

---

## Files

| File | Purpose |
|---|---|
| `examples/08_interrupted_states/server.rb` | Two agents: `OrderAgent` (`input_required`) and `VaultAgent` (`auth_required`) |
| `examples/08_interrupted_states/client.rb` | Drives two separate multi-turn conversations, each as a sequence of `tasks/send` calls |

---

## The scenario

Two independent conversation threads run in sequence:

**Thread A — `input_required`**

1. Client sends "start order" → server returns `input_required` asking "what would you like?"
2. Client sends "one large pizza" with the same `context_id` → server returns `completed` with the order confirmation.

**Thread B — `auth_required`**

1. Client sends "get secret" → server returns `auth_required`.
2. Client sends wrong token → server stays in `auth_required` (repeated challenge).
3. Client sends correct token → server returns `completed` with the protected data.

---

## Key concept — `context_id`

Each conversational turn is a separate `tasks/send` call. The server uses `message.context_id` to look up the in-progress conversation state:

```ruby
# Client — build a message with an explicit context_id
def msg(text, context_id:)
  A2A::Models::Message.new(
    role:       A2A::Models::Types::Role::USER,
    parts:      [A2A::Models::Part.text(text)],
    context_id: context_id
  )
end

context = SecureRandom.uuid

# Turn 1
task1 = client.send_task(message: msg("start order", context_id: context))
# task1.status.state => "input_required"

# Turn 2
task2 = client.send_task(message: msg("one large pizza", context_id: context))
# task2.status.state => "completed"
```

---

## Server — executor state

Each executor keeps a mutex-protected hash keyed by `context_id`:

```ruby
class OrderExecutor < A2A::Server::AgentExecutor
  def initialize
    @pending = {}
    @mutex   = Mutex.new
  end

  def call(ctx)
    cid = ctx.message.context_id

    if @mutex.synchronize { @pending[cid] }
      # Turn 2 — complete the order
      item = ctx.message.text_content.strip
      @mutex.synchronize { @pending.delete(cid) }
      ctx.task.complete!(artifacts: [
        A2A::Models::Artifact.new(
          parts: [A2A::Models::Part.text("Order placed: #{item}")]
        )
      ])
    else
      # Turn 1 — ask what they want
      @mutex.synchronize { @pending[cid] = true }
      ctx.task.require_input!(message: A2A::Models::Message.new(
        role:  A2A::Models::Types::Role::AGENT,
        parts: [A2A::Models::Part.text("What would you like to order?")]
      ))
    end
  end
end
```

The `VaultAgent` follows the same pattern with `require_auth!` and a token check that stays in `auth_required` on a wrong value, demonstrating that the interrupted state is non-terminal and resumable.

---

## Protocol coverage

| Spec section | What the demo shows |
|---|---|
| `input_required` state | Task transitions to an interrupted state; `status.message` carries the question |
| `auth_required` state | Task blocks until the client provides valid credentials |
| Multi-turn conversations | Each follow-up is a new `tasks/send` carrying the same `context_id` |
| `Message.context_id` | Executor uses the message's `contextId` field to thread state across separate task calls |
| `TaskState` interrupted vs terminal | `input_required` and `auth_required` are non-terminal; the task can still complete |
| Rejection on bad auth | VaultAgent stays in `auth_required` on a wrong token, demonstrating repeated challenge |
