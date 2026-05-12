#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/06_push_notifications/server.rb
#
# Demonstrates push notifications: the server delivers out-of-band HTTP POST
# payloads to a client-registered webhook URL as a task progresses, without
# the client needing to hold an open SSE connection.
#
# The executor holds shared references to the push_sender and push_config_store
# so it can deliver after each state change. The same push_config_store is
# passed to Server::Base so the App's pushNotification/* RPC methods read and
# write the same store.

require_relative "../common_config"

# ---------------------------------------------------------------------------
# Executor — 5-step pipeline; delivers a push notification after each step.
# ---------------------------------------------------------------------------
class PushExecutor < A2A::Server::AgentExecutor
  STEPS    = 5
  STEP_SEC = 2.0

  def initialize(push_sender:, push_config_store:)
    @push_sender       = push_sender
    @push_config_store = push_config_store
  end

  def call(ctx)
    ctx.task.start!
    ctx.emit_status
    push_status(ctx)

    STEPS.times do |i|
      sleep STEP_SEC
      return if ctx.task.terminal?

      ctx.task.status = A2A::Models::TaskStatus.new(
        state:   A2A::Models::Types::TaskState::WORKING,
        message: "Step #{i + 1}/#{STEPS} complete"
      )
      ctx.emit_status
      push_status(ctx)
    end

    return if ctx.task.terminal?

    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "result",
        parts: [A2A::Models::Part.text("All #{STEPS} steps finished for task #{ctx.task.id[0, 8]}")]
      )
    ])
    ctx.emit_status(final: true)
    push_status(ctx, final: true)
  end

  private

  def push_status(ctx, final: false)
    config = @push_config_store.get(ctx.task.id)
    return unless config

    event = A2A::Models::TaskStatusUpdateEvent.new(
      task_id:    ctx.task.id,
      context_id: ctx.task.context_id,
      status:     ctx.task.status,
      final:      final
    )
    @push_sender.deliver(config, event)
  end
end

# ---------------------------------------------------------------------------
# Shared push infrastructure — the executor and the App both reference these
# so that RPC-registered configs are visible to the executor at delivery time.
# ---------------------------------------------------------------------------
push_config_store = A2A::Server::PushConfigStore.new
push_sender       = A2A::Server::PushSender.new
executor          = PushExecutor.new(
  push_sender:       push_sender,
  push_config_store: push_config_store
)

# ---------------------------------------------------------------------------
# Agent card — push_notifications: true is required for the RPC methods
# to be accepted by the server.
# ---------------------------------------------------------------------------
card = A2A::Models::AgentCard.new(
  name:         "PushAgent",
  version:      "1.0",
  description:  "Demonstrates out-of-band push notification delivery",
  capabilities: A2A::Models::AgentCapabilities.new(
    streaming:          true,
    push_notifications: true
  ),
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "push_demo",
      description: "Runs a 5-step task and pushes a status update after each step"
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

puts <<~HEREDOC
  Starting PushAgent on http://localhost:9292
    push_notifications: true
    #{PushExecutor::STEPS} steps × #{PushExecutor::STEP_SEC}s = ~#{(PushExecutor::STEPS * PushExecutor::STEP_SEC).to_i}s per task
  Press Ctrl-C to stop.

HEREDOC

A2A.server(
  agent_card:        card,
  executor:          executor,
  push_sender:       push_sender,
  push_config_store: push_config_store
).run
