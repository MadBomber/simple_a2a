# simple_a2a — Design Specification

**Date:** 2026-05-08
**Protocol:** Agent2Agent (A2A) v1.0 (backward compat: v0.3)
**Gem:** `simple_a2a`

---

## Overview

`simple_a2a` is a standalone Ruby gem implementing the Agent2Agent (A2A) protocol — an open standard (Linux Foundation) for communication and interoperability between AI agents. It provides both a client (to call remote A2A agents) and a server (to expose Ruby agents via A2A). It is framework-agnostic but ships a Rack interface compatible with any Rack server; Falcon is the recommended runtime.

It is the A2A sibling of `simple_acp` and shares the same structural conventions.

---

## Protocol Reference

- Specification: https://a2a-protocol.org/latest/specification/
- GitHub: https://github.com/a2aproject/A2A
- Primary binding: JSON-RPC 2.0 over HTTP(S)
- Secondary binding: HTTP+REST
- Streaming: Server-Sent Events (SSE)
- Versions supported: 1.0 (primary), 0.3 (backward compat)

---

## Constraints

- Ruby >= 3.2.0 (uses `Data` for immutable value objects where appropriate)
- Standalone — no Rails dependency
- Async-first — built on the `async` fiber ecosystem throughout
- No `concurrent-ruby` — async-native primitives only
- Two runtime peer dependencies from own ecosystem: `simple_flow`, `typed_bus`
- `webmock` not used in tests (does not intercept `async-http`); use async-http test doubles instead

---

## Directory Structure

```
lib/
  simple_a2a.rb
  simple_a2a/
    version.rb
    errors.rb
    models/
      base.rb
      types.rb
      part.rb
      message.rb
      artifact.rb
      task_status.rb
      task.rb
      stream_response.rb
      send_message_config.rb
      push_notification.rb
      agent_card.rb
      agent_capabilities.rb
      agent_skill.rb
      agent_interface.rb
      security_scheme.rb
    events/
      task_status_update.rb
      task_artifact_update.rb
    jsonrpc/
      request.rb
      response.rb
      error.rb
    server/
      base.rb
      app.rb
      context.rb
      agent_executor.rb
      event_router.rb
      push_sender.rb
      falcon_runner.rb
    client/
      base.rb
      sse.rb
    storage/
      base.rb
      memory.rb
test/
  test_helper.rb
  models/
  events/
  jsonrpc/
  server/
  client/
  storage/
docs/
  superpowers/
    specs/
```

---

## Dependencies

### Runtime

| Gem | Version | Role |
|-----|---------|------|
| `async` | ~> 2.0 | Fiber-based event loop |
| `async-http` | ~> 0.66 | HTTP client, SSE streaming |
| `falcon` | ~> 0.47 | Async Rack HTTP server |
| `roda` | ~> 3.0 | Rack router for server routes |
| `rack` | ~> 3.0 | Rack interface compatibility |
| `jwt` | ~> 2.0 | RS256 push notification signing/verification |
| `simple_flow` | current | AgentExecutor pipeline composition |
| `typed_bus` | current | Per-task event fan-out (SSE + webhooks) |

### Development

| Gem | Role |
|-----|------|
| `minitest` | Test framework |
| `minitest-reporters` | Test output formatting |
| `rack-test` | Server route integration tests |
| `falcon` | In-process server for client integration tests |
| `debug_me` | Debugging (never `puts`) |
| `rake` | Task runner |

---

## Data Model

All models inherit from `SimpleA2a::Models::Base`, which provides:
- `attribute :name, type:, default:, required:` DSL
- Auto-generated accessors
- `self.from_hash(hash)` — camelCase JSON → snake_case Ruby
- `to_h` / `to_json` — snake_case Ruby → camelCase JSON
- `valid?` — validates required fields

### Types (`models/types.rb`)

```ruby
module TaskState
  SUBMITTED       = "submitted"
  WORKING         = "working"
  COMPLETED       = "completed"     # terminal
  FAILED          = "failed"        # terminal
  CANCELED        = "canceled"      # terminal
  REJECTED        = "rejected"      # terminal
  INPUT_REQUIRED  = "input_required"  # interrupted
  AUTH_REQUIRED   = "auth_required"   # interrupted

  TERMINAL    = [COMPLETED, FAILED, CANCELED, REJECTED].freeze
  INTERRUPTED = [INPUT_REQUIRED, AUTH_REQUIRED].freeze
  ACTIVE      = [SUBMITTED, WORKING].freeze
end

module Role
  USER  = "user"
  AGENT = "agent"
end
```

### Part (`models/part.rb`)

OneOf content field (exactly one must be set):

| Field | Type | Notes |
|-------|------|-------|
| `text` | String | Plain text |
| `raw` | String | Base64-encoded binary |
| `url` | String | URL reference |
| `data` | Hash | Structured JSON |
| `media_type` | String | MIME type (optional) |
| `filename` | String | Optional filename |
| `metadata` | Hash | Part-specific metadata |

Factories: `Part.text(str)`, `Part.json(hash)`, `Part.from_url(url, media_type:)`, `Part.binary(bytes, media_type:)`

### Message (`models/message.rb`)

| Field | Type | Required |
|-------|------|----------|
| `message_id` | String | Yes (auto-UUID if omitted) |
| `role` | Role | Yes |
| `parts` | Array\<Part\> | Yes |
| `context_id` | String | No |
| `task_id` | String | No |
| `reference_task_ids` | Array\<String\> | No |
| `metadata` | Hash | No |
| `extensions` | Array\<String\> | No |

Factories: `Message.user(*parts)`, `Message.agent(*parts)`

### Artifact (`models/artifact.rb`)

| Field | Type | Required |
|-------|------|----------|
| `artifact_id` | String | Yes (auto-UUID) |
| `name` | String | No |
| `description` | String | No |
| `parts` | Array\<Part\> | Yes (min 1) |
| `metadata` | Hash | No |
| `extensions` | Array\<String\> | No |

### TaskStatus (`models/task_status.rb`)

| Field | Type | Required |
|-------|------|----------|
| `state` | TaskState | Yes |
| `message` | Message | No |
| `timestamp` | String (ISO 8601) | No (auto-set) |

Predicates: `terminal?`, `interrupted?`, `active?`

### Task (`models/task.rb`)

| Field | Type | Required |
|-------|------|----------|
| `id` | String | Yes (server-generated UUID) |
| `context_id` | String | No (server-generated if absent) |
| `status` | TaskStatus | Yes |
| `artifacts` | Array\<Artifact\> | No |
| `history` | Array\<Message\> | No |
| `metadata` | Hash | No |

State delegation: `task.state`, `task.terminal?`, `task.interrupted?`
Transitions: `task.submit!`, `task.start!`, `task.complete!(artifacts:)`, `task.fail!(message:)`, `task.cancel!`, `task.reject!`, `task.require_input!(message:)`, `task.require_auth!(message:)`

### AgentCard (`models/agent_card.rb`)

Served at `GET /agentCard`. Describes the agent to clients.

| Field | Type | Required |
|-------|------|----------|
| `name` | String | Yes |
| `description` | String | No |
| `version` | String | Yes |
| `provider` | AgentProvider | No |
| `capabilities` | AgentCapabilities | Yes |
| `skills` | Array\<AgentSkill\> | Yes |
| `interfaces` | Array\<AgentInterface\> | Yes |
| `security_schemes` | Array\<SecurityScheme\> | No |
| `security` | Array\<Hash\> | No |
| `extensions` | Array | No |

### AgentProvider (`models/agent_card.rb`)

Simple value object, defined alongside `AgentCard`:

| Field | Type | Required |
|-------|------|----------|
| `name` | String | Yes |
| `url` | String | No |
| `description` | String | No |

### AgentCapabilities (`models/agent_capabilities.rb`)

| Field | Type | Default |
|-------|------|---------|
| `streaming` | Boolean | false |
| `push_notifications` | Boolean | false |
| `extended_agent_card` | Boolean | false |

### AgentSkill (`models/agent_skill.rb`)

| Field | Type | Required |
|-------|------|----------|
| `name` | String | Yes |
| `description` | String | No |
| `input_schema` | Hash | No (JSON Schema) |
| `output_schema` | Hash | No (JSON Schema) |

### AgentInterface (`models/agent_interface.rb`)

| Field | Type | Required |
|-------|------|----------|
| `type` | String | Yes ("json-rpc", "http", "grpc") |
| `url` | String | Yes |
| `version` | String | Yes |

### SecurityScheme (`models/security_scheme.rb`)

Polymorphic — `from_hash` dispatches on `type` field:
- `APIKeySecurityScheme` — `api_key_name`, `in` (header/query)
- `HTTPAuthSecurityScheme` — `scheme` (basic/bearer)
- `OAuth2SecurityScheme` — `flows` hash
- `OpenIdConnectSecurityScheme` — `open_id_connect_url`
- `MutualTlsSecurityScheme`

### PushNotificationConfig (`models/push_notification.rb`)

| Field | Type | Required |
|-------|------|----------|
| `id` | String | Yes (server-generated) |
| `task_id` | String | Yes |
| `webhook_url` | String | Yes |
| `authentication_info` | AuthenticationInfo | No |
| `event_types` | Array\<String\> | No |

`AuthenticationInfo`: `scheme` ("bearer"/"apiKey"), `value`, `header_name`

### SendMessageConfiguration (`models/send_message_config.rb`)

| Field | Type | Default |
|-------|------|---------|
| `accepted_output_modes` | Array\<String\> | [] |
| `task_push_notification_config` | PushNotificationConfig | nil |
| `history_length` | Integer | nil |
| `return_immediately` | Boolean | false |

### StreamResponse (`models/stream_response.rb`)

OneOf container — exactly one is set:
- `task` → Task
- `message` → Message
- `status_update` → TaskStatusUpdateEvent
- `artifact_update` → TaskArtifactUpdateEvent

`type` predicate methods: `task?`, `message?`, `status_update?`, `artifact_update?`

---

## Events

### TaskStatusUpdateEvent (`events/task_status_update.rb`)

| Field | Type | Required |
|-------|------|----------|
| `task_id` | String | Yes |
| `context_id` | String | Yes |
| `status` | TaskStatus | Yes |
| `metadata` | Hash | No |

`sse_format` → `"data: {json}\n\n"` (wrapped in JSON-RPC response envelope)

### TaskArtifactUpdateEvent (`events/task_artifact_update.rb`)

| Field | Type | Required |
|-------|------|----------|
| `task_id` | String | Yes |
| `context_id` | String | Yes |
| `artifact` | Artifact | Yes |
| `append` | Boolean | No |
| `last_chunk` | Boolean | No |
| `metadata` | Hash | No |

---

## JSON-RPC 2.0 Layer (`jsonrpc/`)

### Request (`jsonrpc/request.rb`)

```ruby
{
  "jsonrpc"        => "2.0",
  "method"         => "SendMessage",        # A2A operation name
  "params"         => { ... },              # Operation-specific params
  "id"             => "uuid-or-int",
  "a2a-version"    => "1.0",               # Optional, defaults to "0.3"
  "a2a-extensions" => "uri1,uri2"          # Optional
}
```

Methods: `SendMessage`, `SendStreamingMessage`, `GetTask`, `ListTasks`, `CancelTask`, `SubscribeToTask`, `CreateTaskPushNotificationConfig`, `GetTaskPushNotificationConfig`, `ListTaskPushNotificationConfigs`, `DeleteTaskPushNotificationConfig`, `GetExtendedAgentCard`

### Response (`jsonrpc/response.rb`)

Success: `{ "jsonrpc" => "2.0", "id" => ..., "result" => { ... } }`
Error: `{ "jsonrpc" => "2.0", "id" => ..., "error" => { "code" => ..., "message" => ..., "data" => { "details" => [...] } } }`

### Error Codes (`jsonrpc/error.rb`)

Standard JSON-RPC codes + A2A-specific:

| Constant | Code | A2A Error |
|----------|------|-----------|
| `PARSE_ERROR` | -32700 | — |
| `INVALID_REQUEST` | -32600 | — |
| `METHOD_NOT_FOUND` | -32601 | `UnsupportedOperationError` |
| `INVALID_PARAMS` | -32602 | `ContentTypeNotSupportedError` |
| `INTERNAL_ERROR` | -32603 | — |
| `TASK_NOT_FOUND` | -32001 | `TaskNotFoundError` |
| `TASK_NOT_CANCELABLE` | -32002 | `TaskNotCancelableError` |
| `PUSH_NOT_SUPPORTED` | -32003 | `PushNotificationNotSupportedError` |
| `UNSUPPORTED_OPERATION` | -32004 | `UnsupportedOperationError` |
| `CONTENT_TYPE_NOT_SUPPORTED` | -32005 | `ContentTypeNotSupportedError` |
| `INVALID_AGENT_RESPONSE` | -32006 | `InvalidAgentResponseError` |
| `EXTENSION_REQUIRED` | -32007 | `ExtensionSupportRequiredError` |
| `VERSION_NOT_SUPPORTED` | -32008 | `VersionNotSupportedError` |

---

## Errors (`errors.rb`)

```ruby
module SimpleA2a
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TaskNotFoundError < Error; end
  class TaskNotCancelableError < Error; end
  class PushNotificationNotSupportedError < Error; end
  class UnsupportedOperationError < Error; end
  class ContentTypeNotSupportedError < Error; end
  class InvalidAgentResponseError < Error; end
  class ExtensionSupportRequiredError < Error; end
  class VersionNotSupportedError < Error; end
  class ExtendedAgentCardNotConfiguredError < Error; end
end
```

---

## Server Architecture

### AgentExecutor (`server/agent_executor.rb`)

Abstract base class. Subclasses implement the agent logic.

```ruby
class SimpleA2a::Server::AgentExecutor
  # Subclasses must implement:
  def execute(context)
    # Called when a new task message arrives.
    # Use context.emit_status(state, message:) to update task state.
    # Use context.emit_artifact(artifact) to deliver outputs.
    # Use context.require_input!(message:) to pause and request clarification.
    # Use context.cancel? to check for cancellation.
    raise NotImplementedError
  end

  def cancel(context)
    # Called when CancelTask is received for an in-progress task.
    # Default implementation does nothing (executor checks context.cancel?).
  end
end
```

The executor can optionally compose a `SimpleFlow::Pipeline` internally for multi-step workflows.

### Context (`server/context.rb`)

Provided to the executor during `execute`:

```ruby
class SimpleA2a::Server::Context
  attr_reader :task, :message, :configuration, :storage, :server

  def task_id;    def context_id

  def emit_status(state, message: nil)       # Publishes TaskStatusUpdateEvent
  def emit_artifact(artifact, append: false, last_chunk: true)  # Publishes TaskArtifactUpdateEvent
  def require_input!(prompt_message: nil)    # Transitions task to INPUT_REQUIRED, halts stream
  def require_auth!(prompt_message: nil)     # Transitions task to AUTH_REQUIRED, halts stream
  def cancel?                                # True if CancelTask received
  def log(msg)                               # Logger integration
end
```

### ResumeContext (`server/context.rb`)

Subclass of `Context` used when a task resumes from `INPUT_REQUIRED` or `AUTH_REQUIRED`. Created by `Server::Base` when a `SendMessage` arrives with a `task_id` pointing to an interrupted task.

```ruby
class SimpleA2a::Server::ResumeContext < Context
  attr_reader :resume_message   # The new Message sent by the client to resume the task
end
```

### EventRouter (`server/event_router.rb`)

Wraps `TypedBus::MessageBus`. One bus instance per server; one typed channel per active task ID.

```ruby
class SimpleA2a::Server::EventRouter
  def subscribe(task_id, &block)    # Returns subscription; block receives StreamResponse
  def publish(task_id, event)       # Broadcasts to all subscribers on that channel
  def unsubscribe(task_id, sub)
  def close_channel(task_id)        # Called when task reaches terminal state
end
```

Subscribers:
1. **SSE stream handler** in `app.rb` — writes `event.sse_format` to the open HTTP response
2. **PushSender** — fires outbound webhook POSTs for matching event types

### PushSender (`server/push_sender.rb`)

Subscribes to EventRouter for tasks that have registered `PushNotificationConfig`s. On event:
1. Filters by `event_types` declared in config
2. Signs payload with RS256 JWT (if `authentication_info` scheme is `bearer`)
3. POSTs via `Async::HTTP::Client` to `webhook_url`
4. Logs delivery failures; does not retry by default (retry policy is application concern)

### Server Base (`server/base.rb`)

```ruby
class SimpleA2a::Server::Base
  def initialize(agent_card:, executor_class:, storage: nil, **options)

  # Rack/Falcon entry point
  def to_app    # Returns Roda Rack app
  def run(port: 8000, host: "0.0.0.0")  # Starts Falcon

  # Called by app.rb route handlers:
  def send_message(message, configuration)         # → Task or Message
  def send_streaming_message(message, config)      # → yields StreamResponse events
  def get_task(id, history_length: nil)            # → Task
  def list_tasks(filters)                          # → { tasks:, next_page_token: }
  def cancel_task(id)                              # → Task
  def subscribe_to_task(id)                        # → yields StreamResponse events
  def create_push_config(task_id, config)          # → PushNotificationConfig
  def get_push_config(task_id, config_id)          # → PushNotificationConfig
  def list_push_configs(task_id, pagination)       # → { configs:, next_page_token: }
  def delete_push_config(task_id, config_id)       # → nil
  def agent_card                                   # → AgentCard
  def extended_agent_card(auth_context)            # → AgentCard (or raises)
end
```

### App Routes (`server/app.rb`)

Roda app with both JSON-RPC and HTTP+REST bindings:

**JSON-RPC endpoint:**
- `POST /` — dispatches on `method` field to server base methods

**HTTP+REST endpoints:**
- `POST /messages` — SendMessage
- `POST /messages:stream` — SendStreamingMessage
- `GET /tasks` — ListTasks
- `GET /tasks/:id` — GetTask
- `POST /tasks/:id:cancel` — CancelTask
- `GET /tasks/:id:stream` — SubscribeToTask
- `POST /tasks/:id/pushNotificationConfigs` — CreatePushConfig
- `GET /tasks/:id/pushNotificationConfigs/:config_id` — GetPushConfig
- `GET /tasks/:id/pushNotificationConfigs` — ListPushConfigs
- `DELETE /tasks/:id/pushNotificationConfigs/:config_id` — DeletePushConfig
- `GET /agentCard` — GetAgentCard (public)
- `GET /agentCard:extended` — GetExtendedAgentCard (authenticated)

**Version negotiation:** All routes check `A2A-Version` header (or `a2a-version` in JSON-RPC body). Returns `VersionNotSupportedError` if unsupported.

**SSE response format:**
```
HTTP 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

data: {"jsonrpc":"2.0","id":"...","result":{...}}\n\n
data: {"jsonrpc":"2.0","id":"...","result":{...}}\n\n
```

---

## Client Architecture

### Client Base (`client/base.rb`)

Uses `Async::HTTP::Client` throughout. All methods run inside `Async { }` block; callers can run inside their own `Async` context or use the blocking wrapper.

```ruby
class SimpleA2a::Client::Base
  def initialize(base_url:, a2a_version: "1.0", auth: nil, **options)
    # auth: { type: :bearer, token: "..." } or { type: :api_key, key: "...", header: "X-Api-Key" }

  # Discovery
  def agent_card                              # → AgentCard
  def extended_agent_card                     # → AgentCard (authenticated)

  # Core operations
  def send_message(message, configuration: nil)         # → Task or Message
  def send_streaming_message(message, config: nil, &block)  # yields StreamResponse; or Enumerator
  def get_task(id, history_length: nil)                 # → Task
  def list_tasks(**filters)                             # → { tasks:, next_page_token: }
  def cancel_task(id)                                   # → Task
  def subscribe_to_task(id, &block)                     # yields StreamResponse; or Enumerator

  # Push notification config management
  def create_push_config(task_id, webhook_url:, **opts) # → PushNotificationConfig
  def get_push_config(task_id, config_id)               # → PushNotificationConfig
  def list_push_configs(task_id)                        # → Array<PushNotificationConfig>
  def delete_push_config(task_id, config_id)            # → true

  # Convenience
  def wait_for_task(id, timeout: 60, interval: 1)       # Polls until terminal or timeout → Task
end
```

All requests include:
- `A2A-Version: 1.0` header
- `Content-Type: application/json` (or `application/a2a+json` where spec requires it)
- `Authorization: Bearer ...` (if auth configured)

### SSE Client (`client/sse.rb`)

```ruby
class SimpleA2a::Client::SSE
  def initialize(response)

  include Enumerable
  def each   # Yields StreamResponse objects; fiber-friendly via async-http streaming
end
```

Parses SSE `data:` fields as JSON-RPC response bodies, unwraps `result` into `StreamResponse`.

---

## Storage

### Storage Base (`storage/base.rb`)

```ruby
class SimpleA2a::Storage::Base
  # Tasks
  def get_task(id)                          # → Task or nil
  def save_task(task)                       # → task
  def list_tasks(context_id: nil, status: nil, page_size: 50, page_token: nil,
                 status_timestamp_after: nil, include_artifacts: true)
    # → { tasks: [], next_page_token: nil, total_size: 0 }

  # Push notification configs
  def create_push_config(config)            # → PushNotificationConfig
  def get_push_config(task_id, config_id)   # → PushNotificationConfig or nil
  def list_push_configs(task_id, page_size: 50, page_token: nil)
    # → { configs: [], next_page_token: nil }
  def delete_push_config(task_id, config_id) # → true/false

  def close
end
```

### Memory Storage (`storage/memory.rb`)

Async-safe in-memory implementation using `Async::Mutex` for write coordination. No `concurrent-ruby`. Suitable for development and testing.

---

## Data Flow

### SendMessage (non-streaming, `returnImmediately: false`)

1. Client POSTs JSON-RPC `SendMessage` to server
2. App parses request, validates `A2A-Version`
3. `Server::Base#send_message` creates `Task` (state: SUBMITTED), saves to storage
4. Creates `Context`, calls `executor.execute(context)` inside `Async { }` fiber
5. Executor calls `context.emit_status(:working)` → storage update
6. Executor runs logic, calls `context.emit_artifact(artifact)` → storage update
7. Executor calls `context.emit_status(:completed)` → storage update
8. `send_message` returns completed `Task`
9. App wraps in JSON-RPC response, returns HTTP 200

### SendStreamingMessage

1–4. Same as above
5. App returns HTTP 200 with `Content-Type: text/event-stream` immediately
6. App subscribes to `EventRouter` channel for `task.id`
7. Executor runs in background fiber, publishing events to `EventRouter`
8. EventRouter fan-out delivers each event to the SSE stream handler
9. SSE handler writes `data: {json}\n\n` to open response stream
10. On terminal state, SSE stream closes; EventRouter closes channel

### Multi-turn (INPUT_REQUIRED resume)

1. Executor calls `context.require_input!(prompt_message:)`
2. Task transitions to INPUT_REQUIRED, SSE stream closes
3. Client receives final StreamResponse with INPUT_REQUIRED status
4. Client sends new `SendMessage` with same `task_id` in message
5. Server loads existing task, creates `ResumeContext`, resumes executor

---

## Testing

- **Model tests**: `from_hash` / `to_h` round-trip for every model; `valid?`; state transition predicates
- **JSON-RPC tests**: Request parsing, response serialization, error code mapping
- **Server route tests**: via `rack-test`; both JSON-RPC and HTTP+REST endpoints; version negotiation; SSE response format
- **Client tests**: async-http test doubles; all methods; streaming enumeration; error propagation
- **Storage tests**: CRUD, pagination, filters for `Memory` implementation
- **Integration tests**: In-process Falcon server with a trivial `AgentExecutor`; client sends message, receives streaming events end-to-end

---

## Convenience Top-level Aliases

```ruby
# In lib/simple_a2a.rb
SimpleA2aServer   = SimpleA2a::Server::Base
SimpleA2aClient   = SimpleA2a::Client::Base
SimpleA2aExecutor = SimpleA2a::Server::AgentExecutor
```

---

## Out of Scope (v1.0)

- gRPC binding (JSON-RPC 2.0 + HTTP+REST only)
- Redis and PostgreSQL storage backends (Memory only in v1; separate gems or PRs later)
- Agent Card signing (RS256 card signature verification)
- OpenTelemetry tracing integration
- `simple_a2a-rails` engine
