# Protocol Details

## Transport

All A2A communication uses **JSON-RPC 2.0 over HTTP POST** to a single endpoint (the server root `/`). The AgentCard is served at `GET /agentCard`.

### Request format

```json
{
  "jsonrpc": "2.0",
  "id": "abc-123",
  "method": "tasks/send",
  "params": {
    "message": {
      "messageId": "msg-1",
      "role": "user",
      "parts": [{ "text": "hello", "kind": "text" }]
    }
  }
}
```

### Response format

```json
{
  "jsonrpc": "2.0",
  "id": "abc-123",
  "result": {
    "id": "task-uuid",
    "contextId": "ctx-uuid",
    "status": { "state": "completed", "timestamp": "2026-01-01T00:00:00Z" },
    "artifacts": [ ... ]
  }
}
```

## Methods

| Method | Description |
|---|---|
| `tasks/send` | Send a message, execute synchronously, return completed task |
| `tasks/sendSubscribe` | Send a message, stream events via SSE |
| `tasks/get` | Retrieve a task by ID |
| `tasks/list` | List all tasks |
| `tasks/cancel` | Cancel a non-terminal task |
| `tasks/pushNotification/set` | Register a push notification endpoint |
| `tasks/pushNotification/get` | Retrieve push notification config |
| `tasks/pushNotification/delete` | Remove push notification config |
| `tasks/pushNotification/list` | List push notification configs |

## Error codes

| Code | Constant | Description |
|---|---|---|
| -32700 | `PARSE_ERROR` | Invalid JSON |
| -32600 | `INVALID_REQUEST` | Not a valid JSON-RPC 2.0 object |
| -32601 | `METHOD_NOT_FOUND` | Unknown method |
| -32602 | `INVALID_PARAMS` | Missing or invalid parameters |
| -32603 | `INTERNAL_ERROR` | Unhandled server error |
| -32001 | `TASK_NOT_FOUND` | No task with the given ID |
| -32002 | `TASK_NOT_CANCELABLE` | Task is already in a terminal state |
| -32003 | `PUSH_NOT_SUPPORTED` | Agent doesn't support push notifications |
| -32004 | `UNSUPPORTED_OPERATION` | Operation not supported (e.g. SSE on non-streaming agent) |
| -32005 | `CONTENT_TYPE_NOT_SUPPORTED` | |
| -32006 | `INVALID_AGENT_RESPONSE` | |
| -32007 | `EXTENSION_REQUIRED` | |
| -32008 | `VERSION_NOT_SUPPORTED` | Unsupported A2A-Version header value |

## Version negotiation

Clients may include an `A2A-Version` header. The server accepts `1.0` and `0.3`. Any other value returns a `VERSION_NOT_SUPPORTED` error.

```http
POST / HTTP/1.1
A2A-Version: 1.0
Content-Type: application/json
```

## Task lifecycle

```
submitted
    │
    ▼
working
    │
    ├──→ completed   (terminal)
    ├──→ failed      (terminal)
    ├──→ canceled    (terminal)
    ├──→ rejected    (terminal)
    ├──→ input_required  (interrupted — waiting for user)
    └──→ auth_required   (interrupted — waiting for credentials)
```

Terminal tasks cannot be canceled (`TASK_NOT_CANCELABLE`).  
Interrupted tasks can be resumed by sending a new message.

## Streaming (SSE)

`tasks/sendSubscribe` keeps the HTTP connection open and streams `text/event-stream` events:

```
data: {"jsonrpc":"2.0","result":{"type":"TaskStatusUpdateEvent","taskId":"…","status":{"state":"working"},"final":false}}

data: {"jsonrpc":"2.0","result":{"type":"TaskArtifactUpdateEvent","taskId":"…","artifact":{…},"final":false}}

data: {"jsonrpc":"2.0","result":{"type":"TaskStatusUpdateEvent","taskId":"…","status":{"state":"completed"},"final":true}}
```

Events with `"final": true` signal that the stream is complete.
