# API Reference

## Namespaces

| Namespace | Description |
|---|---|
| [`A2A::Models`](models/index.md) | Data classes — Task, Message, Part, Artifact, AgentCard, events |
| [`A2A::Server`](server/index.md) | Server bootstrap, routing, executor base, context, event routing |
| [`A2A::Client`](client/index.md) | HTTP client (sync JSON-RPC + SSE streaming) |
| [`A2A::Storage`](storage/index.md) | Task persistence — Memory backend, pluggable base |
| `A2A::JsonRpc` | JSON-RPC 2.0 request/response/error layer |

## Top-level module

```ruby
A2A.logger = Logger.new($stdout)   # optional — logs internal warnings

A2A.server(**opts)       # → A2A::Server::Base.new(**opts)
A2A.multi_server(**opts) # → A2A::Server::MultiAgent.new(**opts)
A2A.client(**opts)       # → A2A::Client::Base.new(**opts)
A2A.sse_client(**opts)   # → A2A::Client::SSE.new(**opts)
```

## Constants

```ruby
A2A::VERSION   # => "0.1.0"
```
