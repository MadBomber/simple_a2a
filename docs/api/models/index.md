# Models

All model classes live under `A2A::Models` and inherit from `A2A::Models::Base`, which provides a lightweight attribute DSL with camelCase JSON serialization.

## Part

The atomic content unit in a message or artifact.

```ruby
A2A::Models::Part.text("hello")                               # text part
A2A::Models::Part.json({ key: "value" })                      # JSON data part
A2A::Models::Part.from_url("https://…", media_type: "image/png")  # URL reference
A2A::Models::Part.binary(File.binread("file.pdf"),
                          media_type: "application/pdf",
                          filename: "file.pdf")                # base64-encoded binary
```

| Attribute | Type | Description |
|---|---|---|
| `text` | String | Plain text content |
| `data` | Hash | Structured JSON data |
| `url` | String | URL reference |
| `raw` | String | Base64-encoded binary |
| `media_type` | String | MIME type |
| `filename` | String | Suggested filename |
| `metadata` | Hash | Arbitrary metadata |

**Predicates:** `#text?`, `#json?`, `#url?`, `#raw?`, `#valid?`  
**Decoding:** `#decoded_bytes` → binary string (Base64 decode of `raw`)

---

## Message

A message from a user or agent, composed of one or more Parts.

```ruby
A2A::Models::Message.user("hello")                        # user message with text part
A2A::Models::Message.user("prefix", Part.text("…"))      # mixed content
A2A::Models::Message.agent("I understand")                # agent message
```

| Attribute | Type | Required | Description |
|---|---|---|---|
| `message_id` | String | auto | UUID, auto-generated |
| `role` | String | yes | `"user"` or `"agent"` |
| `parts` | [Part] | yes | Content parts |
| `context_id` | String | | Task context ID |
| `task_id` | String | | Task this message belongs to |
| `reference_task_ids` | [String] | | Related task IDs |
| `metadata` | Hash | | Arbitrary metadata |

**Predicates:** `#user?`, `#agent?`, `#valid?`  
**Helper:** `#text_content` → concatenates all text parts with newlines

---

## Artifact

A structured output produced by an agent.

```ruby
A2A::Models::Artifact.new(
  name:  "report",
  parts: [A2A::Models::Part.text("The answer is 42")]
)
```

| Attribute | Type | Description |
|---|---|---|
| `artifact_id` | String | UUID, auto-generated |
| `name` | String | Artifact identifier |
| `description` | String | Human-readable description |
| `parts` | [Part] | Content parts |
| `metadata` | Hash | Arbitrary metadata |
| `extensions` | Array | Protocol extension data |

Note: `append` and `last_chunk` are **not** Artifact attributes — they are parameters on `ctx.emit_artifact(artifact, append:, last_chunk:)` and on `TaskArtifactUpdateEvent`.

---

## Task

Represents a unit of work. Tasks are created by the server on each `tasks/send` call.

```ruby
task = A2A::Models::Task.new(
  status: A2A::Models::TaskStatus.new(state: "submitted")
)
```

| Method | Description |
|---|---|
| `task.start!` | Transition to `working` |
| `task.complete!(artifacts: […])` | Transition to `completed`, attach artifacts |
| `task.fail!(message: "…")` | Transition to `failed` |
| `task.cancel!` | Transition to `canceled` |
| `task.reject!(message: "…")` | Transition to `rejected` |
| `task.require_input!` | Transition to `input_required` |
| `task.require_auth!` | Transition to `auth_required` |
| `task.terminal?` | True if state is completed/failed/canceled/rejected |
| `task.interrupted?` | True if state is input_required/auth_required |
| `task.state` | Current state string |

---

## TaskStatus

Attached to every Task. Created automatically on transition.

| Attribute | Type | Description |
|---|---|---|
| `state` | String | One of the `Types::TaskState` constants |
| `message` | Message | Optional status message |
| `timestamp` | String | ISO 8601, auto-set to `Time.now.iso8601` |

---

## Types

```ruby
A2A::Models::Types::TaskState::SUBMITTED      # => "submitted"
A2A::Models::Types::TaskState::WORKING        # => "working"
A2A::Models::Types::TaskState::COMPLETED      # => "completed"
A2A::Models::Types::TaskState::FAILED         # => "failed"
A2A::Models::Types::TaskState::CANCELED       # => "canceled"
A2A::Models::Types::TaskState::REJECTED       # => "rejected"
A2A::Models::Types::TaskState::INPUT_REQUIRED # => "input_required"
A2A::Models::Types::TaskState::AUTH_REQUIRED  # => "auth_required"

A2A::Models::Types::TaskState.terminal?(state)    # => true/false
A2A::Models::Types::TaskState.interrupted?(state) # => true/false
A2A::Models::Types::TaskState.active?(state)      # => true/false

A2A::Models::Types::Role::USER   # => "user"
A2A::Models::Types::Role::AGENT  # => "agent"
```

---

## AgentCard

Describes an agent's identity and capabilities for discovery.

```ruby
card = A2A::Models::AgentCard.new(
  name:         "MyAgent",
  version:      "1.0",
  description:  "An example agent",
  capabilities: A2A::Models::AgentCapabilities.new(streaming: true),
  skills:       [A2A::Models::AgentSkill.new(name: "greet")],
  interfaces:   [A2A::Models::AgentInterface.new(
    type: "json-rpc", url: "http://localhost:9292", version: "1.0"
  )]
)
```

### AgentCapabilities

| Attribute | Type | Default | Description |
|---|---|---|---|
| `streaming` | Boolean | false | Supports `tasks/sendSubscribe` |
| `push_notifications` | Boolean | false | Supports webhook push |
| `extended_agent_card` | Boolean | false | Exposes extended AgentCard at `GET /agentCard?extended=true` |

### AgentSkill

| Attribute | Required | Description |
|---|---|---|
| `name` | yes | Skill identifier |
| `description` | | Human-readable description |
| `input_schema` | | JSON Schema describing accepted input |
| `output_schema` | | JSON Schema describing produced output |

### AgentInterface

| Attribute | Description |
|---|---|
| `type` | Binding type: `"json-rpc"`, `"http"`, `"grpc"` |
| `url` | Endpoint URL |
| `version` | Protocol version |

---

## Events

Events are emitted during streaming (`tasks/sendSubscribe`) and via push notifications.

### TaskStatusUpdateEvent

```ruby
A2A::Models::TaskStatusUpdateEvent.new(
  task_id:    task.id,
  context_id: task.context_id,
  status:     task.status,
  final:      true
)
```

### TaskArtifactUpdateEvent

```ruby
A2A::Models::TaskArtifactUpdateEvent.new(
  task_id:    task.id,
  context_id: task.context_id,
  artifact:   artifact,
  append:     false,
  last_chunk: false
)
```

---

## Push notification models

### PushNotificationConfig

```ruby
config = A2A::Models::PushNotificationConfig.new(
  webhook_url:          "https://example.com/hook",
  authentication_info:  A2A::Models::AuthenticationInfo.new(
    scheme: "bearer",
    value:  ""   # not used for JWT; PushSender generates the token from the private key
  )
)
config.valid?   # => true
```

### AuthenticationInfo

| Attribute | Description |
|---|---|
| `scheme` | `"bearer"` (JWT), `"token"` (static), or custom |
| `value` | Token value (used for `"token"` scheme) |
| `header_name` | Override header name (default: `"Authorization"`) |
