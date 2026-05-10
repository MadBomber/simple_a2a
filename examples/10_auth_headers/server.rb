#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/10_auth_headers/server.rb
#
# Demonstrates the headers: option on A2A.client by running a server that
# enforces Bearer token authentication on all RPC calls (POST requests).
# Agent card discovery (GET /agentCard) is intentionally left public.
#
# The middleware wraps the standard rack_app — no library changes required.
# Any Rack middleware (OAuth, mTLS, API key, custom headers) can be layered
# the same way.
#
# Valid token: "super-secret-token"

require_relative "../common_config"

VALID_TOKEN = "super-secret-token"

# ---------------------------------------------------------------------------
# Rack middleware — checks Authorization: Bearer <token> on POST requests.
# Returns a JSON-RPC shaped error so the A2A client can parse it cleanly.
# ---------------------------------------------------------------------------
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
          "jsonrpc" => "2.0",
          "id"      => nil,
          "error"   => {
            "code"    => -32_000,
            "message" => "Unauthorized: valid Bearer token required"
          }
        })
        return [200, { "Content-Type" => "application/json" }, [body]]
      end
    end

    @app.call(env)
  end
end

# ---------------------------------------------------------------------------
# Executor — echoes the input back, confirming the request was authorized.
# ---------------------------------------------------------------------------
class SecureEchoExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    input = ctx.message.text_content.strip
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "reply",
        parts: [A2A::Models::Part.text("[authorized] echo: #{input}")]
      )
    ])
  end
end

# ---------------------------------------------------------------------------
# Agent card and server
# ---------------------------------------------------------------------------
card = A2A::Models::AgentCard.new(
  name:         "SecureAgent",
  version:      "1.0",
  description:  "Requires a Bearer token on all RPC calls; agent card is public",
  capabilities: A2A::Models::AgentCapabilities.new,
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "secure_echo",
      description: "Echoes input — only reachable with a valid Bearer token"
    )
  ],
  interfaces: [
    A2A::Models::AgentInterface.new(
      type:    "json-rpc",
      url:     "http://localhost:9292",
      version: "1.0"
    )
  ]
)

# Build the rack app and wrap it with auth middleware.
inner_app = A2A.server(agent_card: card, executor: SecureEchoExecutor.new).rack_app
auth_app  = BearerAuthMiddleware.new(inner_app, token: VALID_TOKEN)

puts "Starting SecureAgent on http://localhost:9292"
puts "  GET  /agentCard  — public (no auth required)"
puts "  POST /           — requires Authorization: Bearer #{VALID_TOKEN}"
puts "Press Ctrl-C to stop."
puts

A2A::Server::FalconRunner.new(auth_app, port: 9292).run
