#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/12_broker_agent/client.rb
#
# Start the server first:
#   bundle exec ruby examples/12_broker_agent/server.rb
#
# What this demo shows:
#   1. RFC 8615 discovery — broker card fetched from /.well-known/agent-card.json
#      using a plain Net::HTTP GET (no A2A client needed for discovery).
#   2. Broker routing — four queries sent to the broker; each returns a ranked
#      JSON array of matching AgentCards so the client can pick the best match.
#   3. End-to-end dispatch — the client extracts the top agent's URL from its
#      interface declaration and calls that agent directly to get a real answer.
#   4. Standalone verification — each sub-agent is also called directly to
#      confirm it works independently of the broker.

require "net/http"
require "json"
require_relative "../common_config"

BASE_URL   = "http://localhost:9292"
BROKER_URL = BASE_URL

def divider = puts("─" * 70)

# ---------------------------------------------------------------------------
# RFC 8615 discovery — raw HTTP GET on /.well-known/agent-card.json
# ---------------------------------------------------------------------------
puts
puts "=== RFC 8615 Discovery ==="
uri  = URI.parse("#{BASE_URL}/.well-known/agent-card.json")
raw  = Net::HTTP.get(uri)
card_hash = JSON.parse(raw)
puts "  Endpoint : #{uri}"
puts "  Name     : #{card_hash['name']}"
puts "  Version  : #{card_hash['version']}"
puts "  Skills   : #{Array(card_hash['skills']).map { |s| s['name'] }.join(', ')}"
puts

divider

# ---------------------------------------------------------------------------
# Broker routing — send queries and inspect the ranked matches
# ---------------------------------------------------------------------------
broker = A2A.client(url: BROKER_URL)

queries = [
  { label: "Weather query",      text: "What is the weather forecast for Paris today?" },
  { label: "Translation query",  text: "Please translate 'good morning' to Japanese"   },
  { label: "Calculator query",   text: "Calculate 125 * 48"                             },
  { label: "Scheduler query",    text: "Schedule a meeting with the team tomorrow at 9am" },
]

puts
puts "=== Broker Routing — ranked AgentCard matches ==="
puts

routing_results = queries.map do |q|
  task  = broker.send_task(message: A2A::Models::Message.user(q[:text]))
  cards = task.artifacts.first&.parts&.first&.data || []

  puts "  Query : #{q[:label]}"
  puts "          #{q[:text].inspect}"
  cards.each_with_index do |c, i|
    puts "    #{i + 1}. #{c['name']}  — #{c['description']}"
  end
  puts

  { query: q, cards: cards, task_state: task.status.state }
end

divider

# ---------------------------------------------------------------------------
# End-to-end dispatch — call the top-ranked agent directly
# ---------------------------------------------------------------------------
puts
puts "=== End-to-End Dispatch — call top-ranked agent for each query ==="
puts

dispatch_results = routing_results.map do |r|
  top_card = r[:cards].first
  unless top_card
    puts "  #{r[:query][:label]}: no agent matched"
    next { matched: false }
  end

  agent_url = top_card.dig("interfaces", 0, "url")
  agent     = A2A.client(url: agent_url)
  result    = agent.send_task(message: A2A::Models::Message.user(r[:query][:text]))
  reply     = result.artifacts.first&.parts&.first&.text || "(no reply)"

  puts "  #{r[:query][:label]}"
  puts "    Routed to : #{top_card['name']} (#{agent_url})"
  puts "    Result    :"
  reply.each_line { |l| puts "      #{l.chomp}" }
  puts

  { matched: true, agent: top_card["name"], state: result.status.state }
end

divider

# ---------------------------------------------------------------------------
# Standalone sub-agent verification — each agent called directly
# ---------------------------------------------------------------------------
puts
puts "=== Standalone Sub-Agent Verification ==="
puts

standalone_calls = [
  { name: "WeatherAgent",     url: "#{BASE_URL}/agents/weather",    text: "What is the weather in Tokyo today?" },
  { name: "TranslationAgent", url: "#{BASE_URL}/agents/translate",  text: "Translate 'hello' to French"         },
  { name: "CalculatorAgent",  url: "#{BASE_URL}/agents/calculator", text: "What is 99 + 1?"                     },
  { name: "SchedulerAgent",   url: "#{BASE_URL}/agents/scheduler",  text: "Book a dentist appointment Friday"   },
]

standalone_ok = standalone_calls.map do |sc|
  card   = A2A.client(url: sc[:url]).agent_card
  result = A2A.client(url: sc[:url]).send_task(
    message: A2A::Models::Message.user(sc[:text])
  )
  reply  = result.artifacts.first&.parts&.first&.text || "(no reply)"
  state  = result.status.state
  ok     = state == "completed" && !reply.empty?

  puts "  #{sc[:name]} (#{sc[:url]})"
  puts "    Card     : #{card.name} v#{card.version}"
  puts "    State    : #{state}"
  puts "    Reply    : #{reply.lines.first&.strip}"
  puts "    Status   : #{ok ? 'PASS' : 'FAIL'}"
  puts
  ok
end

divider

# ---------------------------------------------------------------------------
# Verification summary
# ---------------------------------------------------------------------------
puts
puts "=== Verification Summary ==="
puts

rfc_ok           = card_hash["name"] == "Service Broker"
routing_ok       = routing_results.all? { |r| r[:task_state] == "completed" && !r[:cards].empty? }
dispatch_ok      = dispatch_results.compact.all? { |r| r[:matched] && r[:state] == "completed" }
standalone_all   = standalone_ok.all?

puts "  RFC 8615 discovery returned broker card : #{rfc_ok         ? 'PASS' : 'FAIL'}"
puts "  All broker routing queries completed    : #{routing_ok     ? 'PASS' : 'FAIL'}"
puts "  All top-ranked dispatch calls completed : #{dispatch_ok    ? 'PASS' : 'FAIL'}"
puts "  All standalone sub-agent calls pass     : #{standalone_all ? 'PASS' : 'FAIL'}"
puts

all_ok = rfc_ok && routing_ok && dispatch_ok && standalone_all
puts(all_ok ? "All assertions passed." : "One or more assertions failed.")
