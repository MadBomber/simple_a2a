# Push Notifications

Push notifications let an A2A server deliver task events to a client-registered webhook, rather than requiring the client to maintain an open SSE connection.

## Overview

1. Client registers a webhook URL via `tasks/pushNotification/set`
2. Server delivers `TaskStatusUpdateEvent` and `TaskArtifactUpdateEvent` to the URL
3. Requests are signed with RS256 JWT (optional but recommended)

## Server setup

Create a `PushSender` with an RS256 private key:

```ruby
require "openssl"

private_key = OpenSSL::PKey::RSA.generate(2048)

push_sender = A2A::Server::PushSender.new(
  private_key: private_key,
  key_id:      "my-key-2026",
  issuer:      "my-agent"
)

server = A2A::Server::Base.new(
  agent_card:  card,
  executor:    MyExecutor.new,
  push_sender: push_sender
)
```

Advertise push notification support in your AgentCard:

```ruby
capabilities = A2A::Models::AgentCapabilities.new(
  push_notifications: true
)
```

## Delivering events from your executor

Call `push_sender.deliver` with the stored `PushNotificationConfig` and an event:

```ruby
class MyExecutor < A2A::Server::AgentExecutor
  def initialize(push_sender:)
    @push_sender = push_sender
  end

  def call(ctx)
    ctx.task.complete!(artifacts: [ … ])
    event = A2A::Models::TaskStatusUpdateEvent.new(
      task_id:    ctx.task.id,
      context_id: ctx.task.context_id,
      status:     ctx.task.status,
      final:      true
    )
    config = # retrieve PushNotificationConfig registered by the client
    @push_sender.deliver(config, event)
  end
end
```

`deliver` returns `true` on HTTP 2xx, `false` on failure. Failures are logged via `A2A.logger` but not raised.

## Authentication schemes

### Bearer (RS256 JWT)

A JWT is generated and sent as `Authorization: Bearer <token>`. The token payload includes:

```json
{
  "iss": "my-agent",
  "iat": 1700000000,
  "exp": 1700000300,
  "payload_hash": "<SHA-256 hex of the request body>"
}
```

```ruby
auth = A2A::Models::AuthenticationInfo.new(scheme: "bearer")
```

### Static token

```ruby
auth = A2A::Models::AuthenticationInfo.new(
  scheme:      "token",
  value:       "secret-webhook-token",
  header_name: "X-Webhook-Token"   # optional, defaults to "Authorization"
)
```

Sent as `X-Webhook-Token: Token secret-webhook-token`.

## PushSender without a private key

If no `private_key` is provided, the JWT token is the literal string `"no-key"`. This is useful for local development without RSA setup:

```ruby
push_sender = A2A::Server::PushSender.new  # no args
```
