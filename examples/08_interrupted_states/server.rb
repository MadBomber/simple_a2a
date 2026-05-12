#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/08_interrupted_states/server.rb
#
# Two agents on one port demonstrating the two interrupted task states:
#
#   /order  — uses input_required to ask the user what they want before
#              completing the order
#   /vault  — uses auth_required to demand a token before revealing data
#
# Each turn from the client is a separate tasks/send call. The executors
# use message.context_id as a conversation key to distinguish first turns
# from follow-ups.

require_relative "../common_config"

BASE_URL = "http://localhost:9292"

# ---------------------------------------------------------------------------
# OrderExecutor — demonstrates input_required.
#
# Turn 1: any message → input_required: "What would you like?"
# Turn 2: message containing a menu item → completed with confirmation
# ---------------------------------------------------------------------------
class OrderExecutor < A2A::Server::AgentExecutor
  MENU = %w[pizza pasta salad].freeze

  def initialize
    @pending = {}
    @mutex   = Mutex.new
  end

  def call(ctx)
    conv_id = ctx.message.context_id
    input   = ctx.message.text_content.strip.downcase
    state   = @mutex.synchronize { @pending[conv_id] }

    if state.nil?
      @mutex.synchronize { @pending[conv_id] = :awaiting_item }
      ctx.task.require_input!(
        message: "What would you like to order? Options: #{MENU.join(', ')}"
      )
    else
      @mutex.synchronize { @pending.delete(conv_id) }
      item = MENU.find { |m| input.include?(m) }

      if item
        ctx.task.complete!(artifacts: [
          A2A::Models::Artifact.new(
            name:  "confirmation",
            parts: [A2A::Models::Part.text("Order confirmed: #{item}! It will be ready in 20 minutes.")]
          )
        ])
      else
        ctx.task.fail!(message: "Unknown item '#{input}'. Please choose from: #{MENU.join(', ')}")
      end
    end
  end
end

# ---------------------------------------------------------------------------
# VaultExecutor — demonstrates auth_required.
#
# Turn 1: any message → auth_required: "Provide your access token"
# Turn 2: correct token → completed with secret data
#          wrong token  → auth_required again (stays blocked)
# ---------------------------------------------------------------------------
class VaultExecutor < A2A::Server::AgentExecutor
  SECRET_TOKEN = "open-sesame"
  SECRET_DATA  = "The treasure is buried under the old oak tree at coordinates 48.8566°N, 2.3522°E."

  def initialize
    @pending = {}
    @mutex   = Mutex.new
  end

  def call(ctx)
    conv_id = ctx.message.context_id
    input   = ctx.message.text_content.strip
    state   = @mutex.synchronize { @pending[conv_id] }

    if state.nil?
      @mutex.synchronize { @pending[conv_id] = :awaiting_token }
      ctx.task.require_auth!(message: "Access restricted. Provide your token to continue.")
    elsif input == SECRET_TOKEN
      @mutex.synchronize { @pending.delete(conv_id) }
      ctx.task.complete!(artifacts: [
        A2A::Models::Artifact.new(
          name:  "secret",
          parts: [A2A::Models::Part.text(SECRET_DATA)]
        )
      ])
    else
      ctx.task.require_auth!(message: "Invalid token. Try again.")
    end
  end
end

# ---------------------------------------------------------------------------
# Agent cards
# ---------------------------------------------------------------------------
def make_card(name:, description:, skill:, path:)
  A2A::Models::AgentCard.new(
    name:         name,
    version:      "1.0",
    description:  description,
    capabilities: A2A::Models::AgentCapabilities.new,
    skills:       [A2A::Models::AgentSkill.new(name: skill, description: description)],
    interfaces:   [A2A::Models::AgentInterface.new(
      type: "json-rpc", url: "#{BASE_URL}#{path}", version: "1.0"
    )]
  )
end

order_card = make_card(
  name:        "OrderAgent",
  description: "Takes food orders — pauses with input_required to ask what the user wants",
  skill:       "order",
  path:        "/order"
)

vault_card = make_card(
  name:        "VaultAgent",
  description: "Guards secret data — pauses with auth_required until a valid token is provided",
  skill:       "vault",
  path:        "/vault"
)

puts <<~HEREDOC
  Starting interrupted-states server on #{BASE_URL}
    /order  → OrderAgent  (demonstrates input_required)
    /vault  → VaultAgent  (demonstrates auth_required)
  Press Ctrl-C to stop.

HEREDOC

A2A.multi_server(
  agents: {
    "/order" => { agent_card: order_card, executor: OrderExecutor.new },
    "/vault" => { agent_card: vault_card, executor: VaultExecutor.new }
  },
  port: 9292
).run
