#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/03_llm_research/server.rb
#
# Requires:
#   ANTHROPIC_API_KEY — for the Anthropic research agent and the evaluator
#   OPENAI_API_KEY    — for the OpenAI research agent
#
# Agents hosted at:
#   http://localhost:9292/anthropic  — claude-sonnet-4-6 researcher
#   http://localhost:9292/openai     — gpt-4o researcher
#   http://localhost:9292/evaluator  — claude-sonnet-4-6 evaluator

require_relative "../common_config"
require "ruby_llm"
require "async/http/faraday"

# Make ruby_llm use the async-http Faraday adapter so LLM API calls are
# fiber-aware inside Falcon's reactor, enabling true SSE streaming.
RubyLLM::Connection.prepend(Module.new do
  private

  def setup_middleware(faraday)
    faraday.request :multipart
    faraday.request :json
    faraday.response :json
    faraday.adapter :async_http
    faraday.use :llm_errors, provider: @provider
  end
end)

%w[ANTHROPIC_API_KEY OPENAI_API_KEY].each do |key|
  abort "#{key} is not set" unless ENV[key]
end

RubyLLM.configure do |c|
  c.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  c.openai_api_key    = ENV["OPENAI_API_KEY"]
end

# ---------------------------------------------------------------------------
# Shared research prompt
# ---------------------------------------------------------------------------
RESEARCH_PROMPT = <<~PROMPT
  Research the following topic thoroughly. Provide a comprehensive, well-structured
  response covering key concepts, history, current state, applications, and future
  directions. Topic: %s
PROMPT

# ---------------------------------------------------------------------------
# Executors
# ---------------------------------------------------------------------------
module StreamingExecutor
  private

  def stream_llm(ctx, model, prompt)
    ctx.task.start!
    ctx.emit_status

    first = true
    prev  = nil

    RubyLLM.chat(model: model).ask(prompt) do |chunk|
      text = chunk.content.to_s
      next if text.empty?

      if prev
        ctx.emit_artifact(
          A2A::Models::Artifact.new(
            index: 0, parts: [A2A::Models::Part.text(prev)],
            append: !first, last_chunk: false
          ),
          append: !first, last_chunk: false
        )
        first = false
      end
      prev = text
    end

    if prev
      ctx.emit_artifact(
        A2A::Models::Artifact.new(
          index: 0, parts: [A2A::Models::Part.text(prev)],
          append: !first, last_chunk: true
        ),
        append: !first, last_chunk: true
      )
    end

    ctx.task.complete!
    ctx.emit_status(final: true)
  end
end

class AnthropicResearchExecutor < A2A::Server::AgentExecutor
  include StreamingExecutor
  MODEL = "claude-sonnet-4-6"

  def call(ctx)
    topic = ctx.message.parts.filter_map(&:text).join(" ").strip
    raise A2A::InvalidParamsError, "topic is required" if topic.empty?
    stream_llm(ctx, MODEL, RESEARCH_PROMPT % topic)
  end
end

class OpenAIResearchExecutor < A2A::Server::AgentExecutor
  include StreamingExecutor
  MODEL = "gpt-5.4"

  def call(ctx)
    topic = ctx.message.parts.filter_map(&:text).join(" ").strip
    raise A2A::InvalidParamsError, "topic is required" if topic.empty?
    stream_llm(ctx, MODEL, RESEARCH_PROMPT % topic)
  end
end

class EvaluatorExecutor < A2A::Server::AgentExecutor
  include StreamingExecutor
  MODEL = "claude-sonnet-4-6"

  def call(ctx)
    prompt = ctx.message.parts.filter_map(&:text).join("\n").strip
    raise A2A::InvalidParamsError, "evaluation prompt is required" if prompt.empty?
    stream_llm(ctx, MODEL, prompt)
  end
end

# ---------------------------------------------------------------------------
# Agent cards
# ---------------------------------------------------------------------------
def research_card(name:, model:, path:)
  A2A::Models::AgentCard.new(
    name:        name,
    version:     "1.0",
    description: "Researches topics using #{model}",
    capabilities: A2A::Models::AgentCapabilities.new(streaming: true),
    skills: [
      A2A::Models::AgentSkill.new(
        name:        "research",
        description: "Deep research on any topic"
      )
    ],
    interfaces: [
      A2A::Models::AgentInterface.new(
        type:    "json-rpc",
        url:     "http://localhost:9292#{path}",
        version: "1.0"
      )
    ]
  )
end

anthropic_card = research_card(
  name:  "AnthropicResearchAgent",
  model: AnthropicResearchExecutor::MODEL,
  path:  "/anthropic"
)

openai_card = research_card(
  name:  "OpenAIResearchAgent",
  model: OpenAIResearchExecutor::MODEL,
  path:  "/openai"
)

evaluator_card = A2A::Models::AgentCard.new(
  name:        "EvaluatorAgent",
  version:     "1.0",
  description: "Evaluates and compares research responses from multiple agents",
  capabilities: A2A::Models::AgentCapabilities.new(streaming: true),
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "evaluate",
      description: "Compare two research responses and determine which is more extensive"
    )
  ],
  interfaces: [
    A2A::Models::AgentInterface.new(
      type:    "json-rpc",
      url:     "http://localhost:9292/evaluator",
      version: "1.0"
    )
  ]
)

# ---------------------------------------------------------------------------
# Start multi-agent server
# ---------------------------------------------------------------------------
puts <<~HEREDOC
  Starting multi-agent research server on http://localhost:9292
    /anthropic  → #{AnthropicResearchExecutor::MODEL}
    /openai     → #{OpenAIResearchExecutor::MODEL}
    /evaluator  → #{EvaluatorExecutor::MODEL} (evaluator)
  Press Ctrl-C to stop.

HEREDOC

A2A.multi_server(
  agents: {
    "/anthropic" => { agent_card: anthropic_card, executor: AnthropicResearchExecutor.new },
    "/openai"    => { agent_card: openai_card,    executor: OpenAIResearchExecutor.new },
    "/evaluator" => { agent_card: evaluator_card, executor: EvaluatorExecutor.new }
  },
  port: 9292
).run
