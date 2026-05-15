#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/12_broker_agent/server.rb
#
# A BrokerServer hosts a routing agent at the server root alongside four
# specialist sub-agents. Clients send their request to the broker and receive
# a ranked list of matching AgentCards. They then call the best-matched agent
# directly.
#
# Layout on http://localhost:9292 :
#   /                      → Service Broker  (auto-generated card + BrokerExecutor)
#   /.well-known/agent-card.json  → RFC 8615-compliant broker card discovery
#   /agents/weather        → WeatherAgent
#   /agents/translate      → TranslationAgent
#   /agents/calculator     → CalculatorAgent
#   /agents/scheduler      → SchedulerAgent

require_relative "../common_config"

BASE_URL = "http://localhost:9292"

# ---------------------------------------------------------------------------
# WeatherExecutor — returns a mock weather forecast for a given location.
# ---------------------------------------------------------------------------
class WeatherExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    location = extract_location(ctx.message.text_content)
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "forecast",
        parts: [A2A::Models::Part.text(
          "Forecast for #{location}:\n" \
          "  Temperature: 22°C (high) / 15°C (low)\n" \
          "  Conditions:  Partly cloudy with light winds from the SW\n" \
          "  UV index:    4 (moderate)\n" \
          "  Humidity:    62%"
        )]
      )
    ])
  end

  private

  def extract_location(text)
    if (m = text.match(/(?:for|in)\s+([A-Z][a-zA-Z\s,]+?)(?:\s+today|\s+tomorrow|\s+this|\s*[?.]?\s*$)/))
      m[1].strip
    else
      "the requested location"
    end
  end
end

# ---------------------------------------------------------------------------
# TranslationExecutor — translates common phrases into a target language.
# ---------------------------------------------------------------------------
class TranslationExecutor < A2A::Server::AgentExecutor
  PHRASES = {
    "good morning"  => { "french" => "bonjour",          "spanish" => "buenos días",  "japanese" => "おはようございます", "german" => "guten morgen" },
    "good night"    => { "french" => "bonne nuit",        "spanish" => "buenas noches", "japanese" => "おやすみなさい",      "german" => "gute nacht" },
    "hello"         => { "french" => "bonjour",           "spanish" => "hola",           "japanese" => "こんにちは",         "german" => "hallo" },
    "goodbye"       => { "french" => "au revoir",         "spanish" => "adiós",          "japanese" => "さようなら",         "german" => "auf wiedersehen" },
    "thank you"     => { "french" => "merci",             "spanish" => "gracias",        "japanese" => "ありがとう",         "german" => "danke" },
    "please"        => { "french" => "s'il vous plaît",   "spanish" => "por favor",      "japanese" => "お願いします",       "german" => "bitte" },
  }.freeze

  def call(ctx)
    text   = ctx.message.text_content.downcase
    phrase = PHRASES.keys.find { |p| text.include?(p) } || "hello"
    lang   = %w[french spanish japanese german].find { |l| text.include?(l) } || "french"
    result = PHRASES.dig(phrase, lang) || "[phrase not in demo dictionary]"
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "translation",
        parts: [A2A::Models::Part.text("\"#{phrase.capitalize}\" in #{lang.capitalize}: #{result}")]
      )
    ])
  end
end

# ---------------------------------------------------------------------------
# CalculatorExecutor — handles arithmetic and compound interest calculations.
# ---------------------------------------------------------------------------
class CalculatorExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    input = ctx.message.text_content
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "result",
        parts: [A2A::Models::Part.text(compute(input))]
      )
    ])
  end

  private

  def compute(text)
    if text.match?(/compound|interest/i)
      compound_interest(text)
    elsif (m = text.match(/(\d+(?:\.\d+)?)\s*([\+\-\*\/])\s*(\d+(?:\.\d+)?)/))
      simple_arithmetic(m[1].to_f, m[2], m[3].to_f)
    else
      "Result: 42  (demonstration value — send an arithmetic expression for a real answer)"
    end
  end

  def compound_interest(text)
    principal = extract_number(text, /\$?([\d,]+)/) || 1_000
    rate      = extract_number(text, /([\d.]+)\s*%/) || 5
    years     = extract_number(text, /([\d]+)\s*year/) || 10
    amount    = principal * ((1 + rate / 100.0)**years)
    "Compound interest:\n" \
      "  Principal:      $#{format("%.2f", principal)}\n" \
      "  Rate:           #{rate}% per year\n" \
      "  Term:           #{years.to_i} years\n" \
      "  Final amount:   $#{format("%.2f", amount)}\n" \
      "  Interest earned:$#{format("%.2f", amount - principal)}"
  end

  def simple_arithmetic(a, op, b)
    result = case op
             when "+" then a + b
             when "-" then a - b
             when "*" then a * b
             when "/" then b.zero? ? "undefined (division by zero)" : a / b
             end
    "#{a} #{op} #{b} = #{result}"
  end

  def extract_number(text, pattern)
    m = text.match(pattern)
    m ? m[1].gsub(",", "").to_f : nil
  end
end

# ---------------------------------------------------------------------------
# SchedulerExecutor — confirms a scheduling request with a confirmation ID.
# ---------------------------------------------------------------------------
class SchedulerExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    request = ctx.message.text_content.strip
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "confirmation",
        parts: [A2A::Models::Part.text(
          "Scheduled: #{request}\n" \
          "  Confirmation: SCH-#{rand(10_000..99_999)}\n" \
          "  Reminder:     1 hour before\n" \
          "  Status:       confirmed"
        )]
      )
    ])
  end
end

# ---------------------------------------------------------------------------
# Agent cards — name, description, and skills determine broker ranking.
# ---------------------------------------------------------------------------
def agent_card(name:, description:, skills:, path:)
  A2A::Models::AgentCard.new(
    name:         name,
    version:      "1.0",
    description:  description,
    capabilities: A2A::Models::AgentCapabilities.new,
    skills:       skills.map { |s|
      A2A::Models::AgentSkill.new(name: s[:name], description: s[:desc])
    },
    interfaces: [
      A2A::Models::AgentInterface.new(
        type: "json-rpc", url: "#{BASE_URL}#{path}", version: "1.0"
      )
    ]
  )
end

weather_card = agent_card(
  name:        "WeatherAgent",
  description: "Provides weather forecasts and climate conditions for any location worldwide",
  skills:      [
    { name: "weather forecast", desc: "Current and future weather conditions by location" },
    { name: "climate",          desc: "Temperature, precipitation, humidity, and UV index" },
  ],
  path:        "/agents/weather"
)

translate_card = agent_card(
  name:        "TranslationAgent",
  description: "Translates words and phrases between English, French, Spanish, Japanese, and German",
  skills:      [
    { name: "translate",  desc: "Translate text between supported languages" },
    { name: "language",   desc: "Phrase translation and language conversion" },
  ],
  path:        "/agents/translate"
)

calculator_card = agent_card(
  name:        "CalculatorAgent",
  description: "Performs arithmetic calculations and compound interest formulas",
  skills:      [
    { name: "calculate",         desc: "Basic and advanced arithmetic expressions" },
    { name: "math",              desc: "Mathematical formulas and calculations" },
    { name: "compound interest", desc: "Principal, rate, term → final amount and interest earned" },
  ],
  path:        "/agents/calculator"
)

scheduler_card = agent_card(
  name:        "SchedulerAgent",
  description: "Books meetings, appointments, and calendar events with confirmation",
  skills:      [
    { name: "schedule",    desc: "Create and confirm calendar appointments" },
    { name: "meeting",     desc: "Team meetings and recurring events" },
    { name: "appointment", desc: "One-on-one and group appointments" },
  ],
  path:        "/agents/scheduler"
)

# ---------------------------------------------------------------------------
# Start the broker server — no custom card or executor needed.
# ---------------------------------------------------------------------------
puts "Starting BrokerServer on #{BASE_URL}"
puts
puts "  /                           → Service Broker"
puts "  /.well-known/agent-card.json→ RFC 8615 discovery endpoint"
puts "  /agents/weather             → WeatherAgent"
puts "  /agents/translate           → TranslationAgent"
puts "  /agents/calculator          → CalculatorAgent"
puts "  /agents/scheduler           → SchedulerAgent"
puts
puts "Press Ctrl-C to stop."
puts

A2A.broker_server(
  agents: {
    "/agents/weather"    => { agent_card: weather_card,    executor: WeatherExecutor.new },
    "/agents/translate"  => { agent_card: translate_card,  executor: TranslationExecutor.new },
    "/agents/calculator" => { agent_card: calculator_card, executor: CalculatorExecutor.new },
    "/agents/scheduler"  => { agent_card: scheduler_card,  executor: SchedulerExecutor.new },
  },
  port: 9292
).run
