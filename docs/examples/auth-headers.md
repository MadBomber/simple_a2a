# 10 Auth Headers

**Run it:**

```bash
bundle exec ruby examples/run 10_auth_headers
```

**What it shows:** injecting custom HTTP headers (Bearer token) into every client request, and wrapping the server with Rack middleware to enforce them.

---

## Files

| File | Purpose |
|---|---|
| `examples/10_auth_headers/server.rb` | `BearerAuthMiddleware` wraps the standard `rack_app`; agent card stays public |
| `examples/10_auth_headers/client.rb` | Two clients — one without headers (rejected) and one with (accepted) |

---

## The scenario

The server enforces a Bearer token on all `POST /` (RPC) requests. `GET /agentCard` is deliberately left public so agents remain discoverable without credentials.

Two clients are created with the same URL:

```ruby
unauth_client = A2A.client(url: URL)
auth_client   = A2A.client(url: URL, headers: { "Authorization" => "Bearer #{TOKEN}" })
```

- `unauth_client.agent_card` → succeeds (GET is public)
- `unauth_client.send_task(...)` → raises `A2A::Error` ("Unauthorized")
- `auth_client.send_task(...)` → succeeds

---

## Server — Rack middleware composition

The middleware pattern keeps the library unchanged:

```ruby
class BearerAuthMiddleware
  def initialize(app, token:)
    @app   = app
    @token = token
  end

  def call(env)
    if env["REQUEST_METHOD"] == "POST"
      auth = env["HTTP_AUTHORIZATION"].to_s
      unless auth == "Bearer #{@token}"
        body = JSON.generate({
          "jsonrpc" => "2.0", "id" => nil,
          "error"   => { "code" => -32_000, "message" => "Unauthorized: valid Bearer token required" }
        })
        return [200, { "Content-Type" => "application/json" }, [body]]
      end
    end
    @app.call(env)
  end
end

inner_app = A2A.server(agent_card: card, executor: SecureEchoExecutor.new).rack_app
auth_app  = BearerAuthMiddleware.new(inner_app, token: VALID_TOKEN)
A2A::Server::FalconRunner.new(auth_app, port: 9292).run
```

The middleware returns a JSON-RPC shaped error body (not a bare HTTP 401) so the `A2A::Error` rescue path on the client works without special-casing.

---

## The `headers:` option

`A2A.client(headers:)` and `A2A.sse_client(headers:)` accept any `Hash` of header name → value pairs, which are merged into every request:

```ruby
# Bearer token
A2A.client(url: URL, headers: { "Authorization" => "Bearer secret" })

# API key
A2A.client(url: URL, headers: { "X-Api-Key" => "key123" })

# Multiple headers
A2A.client(url: URL, headers: {
  "Authorization" => "Bearer token",
  "X-Tenant-Id"   => "acme"
})
```

The same option applies to `A2A.sse_client` for streaming subscriptions.

---

## Protocol coverage

| Spec section | What the demo shows |
|---|---|
| `A2A.client(headers:)` | `headers: { "Authorization" => "Bearer token" }` appended to every request |
| `AgentCard` public discovery | `GET /agentCard` succeeds without authentication — agents are discoverable |
| Bearer token authentication | `Authorization: Bearer <token>` header checked on all POST (RPC) requests |
| Rack middleware composition | `BearerAuthMiddleware.new(rack_app, token:)` wraps the standard app without library changes |
| JSON-RPC error on rejection | Middleware returns a well-formed JSON-RPC error body so the client can rescue `A2A::Error` |
| Header flexibility | The same `headers:` option supports API keys, custom schemes, and any HTTP header |
