#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/13_custom_broker/client.rb
#
# Start the server first:
#   bundle exec ruby examples/13_custom_broker/server.rb
#
# What this demo shows:
#   1. Custom broker card — fetched from /.well-known/agent-card.json; advertises
#      the IDF + synonym-expansion skills rather than the default "Agent Matcher".
#   2. Synonym expansion — queries using "forex", "shares", "baking", "discover"
#      score correctly even though those words don't appear in any agent card.
#      The default keyword broker would return no match or a wrong match.
#   3. IDF-weighted scoring — "exchange rate" scores higher for CurrencyAgent than
#      common terms like "current" or "information" that appear in every agent.
#   4. Confidence metadata — each returned AgentCard carries brokerMeta.confidence
#      and brokerMeta.matchedTerms so the client can make informed dispatch choices.
#   5. Threshold fallback — a deliberately vague query ("Tell me something") clears
#      no agents above MIN_CONFIDENCE; the broker falls back to the top 2 with low
#      confidence values, signalling the client that routing is uncertain.
#   6. End-to-end dispatch — client picks the top-confidence agent and calls it.

require "net/http"
require "json"
require_relative "../common_config"

BASE_URL   = "http://localhost:9292"
BROKER_URL = BASE_URL

def divider = puts("─" * 72)

def print_ranked(cards_with_meta)
  cards_with_meta.each_with_index do |c, i|
    meta  = c["brokerMeta"] || {}
    conf  = meta["confidence"]  ? format("%.3f", meta["confidence"])  : "n/a"
    terms = meta["matchedTerms"] || []
    puts "    #{i + 1}. #{c['name'].ljust(20)} confidence=#{conf}  matched=#{terms.inspect}"
  end
end

# ---------------------------------------------------------------------------
# 1. RFC 8615 discovery — confirm we get the custom broker card
# ---------------------------------------------------------------------------
puts
puts "=== RFC 8615 Discovery ==="
raw       = Net::HTTP.get(URI.parse("#{BASE_URL}/.well-known/agent-card.json"))
card_hash = JSON.parse(raw)
puts "  Name     : #{card_hash['name']}"
puts "  Version  : #{card_hash['version']}"
puts "  Skills   : #{Array(card_hash['skills']).map { |s| s['name'] }.join(' | ')}"
puts
divider

# ---------------------------------------------------------------------------
# 2. Synonym-expansion queries — terms not in any agent card
# ---------------------------------------------------------------------------
puts
puts "=== Synonym Expansion ==="
puts "    (queries use words absent from all agent cards)"
puts

broker = A2A.client(url: BROKER_URL)

synonym_queries = [
  {
    label: "forex query",
    text:  "What is the current EUR/USD forex rate?",
    note:  '"forex" is absent from all cards; expands to: currency exchange rate',
    expect: "CurrencyAgent",
  },
  {
    label: "shares query",
    text:  "What price are Apple shares trading at right now?",
    note:  '"shares" expands to: stock equity market',
    expect: "StockAgent",
  },
  {
    label: "baking query",
    text:  "I need help baking a chocolate cake",
    note:  '"baking" expands to: recipe cooking',
    expect: "RecipeAgent",
  },
  {
    label: "discover query",
    text:  "Who discovered penicillin and in what year?",
    note:  '"discover" expands to: trivia knowledge',
    expect: "TriviaAgent",
  },
  {
    label: "latest query",
    text:  "What are the latest headlines about climate change?",
    note:  '"latest" expands to: news events current',
    expect: "NewsAgent",
  },
]

synonym_results = synonym_queries.map do |q|
  task  = broker.send_task(message: A2A::Models::Message.user(q[:text]))
  cards = task.artifacts.first&.parts&.first&.data || []

  top_name = cards.first&.dig("name")
  pass     = top_name == q[:expect]

  puts "  #{q[:label]} — #{pass ? 'PASS' : 'FAIL'}"
  puts "    Query  : #{q[:text].inspect}"
  puts "    Note   : #{q[:note]}"
  print_ranked(cards)
  puts

  { pass: pass, cards: cards }
end

divider

# ---------------------------------------------------------------------------
# 3. IDF scoring contrast — common vs. discriminating terms
# ---------------------------------------------------------------------------
puts
puts "=== IDF Scoring Contrast ==="
puts "    (discriminating terms rank their specialist agent higher than common terms)"
puts

idf_queries = [
  {
    label:  "discriminating: 'risotto recipe'",
    text:   "How do I make risotto?",
    note:   '"risotto" in RecipeAgent skill desc only — high IDF; other agents score 0',
    expect: "RecipeAgent",
  },
  {
    label:  "discriminating: 'stock quote TSLA'",
    text:   "Get me a stock quote for TSLA",
    note:   '"stock" and "quote" are unique to StockAgent, giving high IDF weight',
    expect: "StockAgent",
  },
  {
    label:  "ambiguous: 'current information'",
    text:   "I need some current information",
    note:   '"current" and "information" appear across many agents — lower IDF, scores spread out',
    expect: nil,  # no single winner expected
  },
]

idf_results = idf_queries.map do |q|
  task  = broker.send_task(message: A2A::Models::Message.user(q[:text]))
  cards = task.artifacts.first&.parts&.first&.data || []

  top_name = cards.first&.dig("name")
  pass = q[:expect].nil? ? true : (top_name == q[:expect])

  puts "  #{q[:label]} — #{pass ? 'PASS' : 'FAIL'}"
  puts "    Query  : #{q[:text].inspect}"
  puts "    Note   : #{q[:note]}"
  print_ranked(cards)
  puts

  { pass: pass, cards: cards }
end

divider

# ---------------------------------------------------------------------------
# 4. Threshold fallback — vague query, no clear winner
# ---------------------------------------------------------------------------
puts
puts "=== Confidence Threshold Fallback ==="
puts "    (vague query → no agent clears MIN_CONFIDENCE → broker returns top 2)"
puts

vague_task  = broker.send_task(message: A2A::Models::Message.user("Tell me something interesting"))
vague_cards = vague_task.artifacts.first&.parts&.first&.data || []

puts "  Query  : 'Tell me something interesting'"
puts "  Result : #{vague_cards.size} agent(s) returned (fallback to top 2 when nothing clears threshold)"
print_ranked(vague_cards)
fallback_ok = vague_cards.size <= 2
puts
divider

# ---------------------------------------------------------------------------
# 5. End-to-end dispatch — call top-confidence agent for each synonym query
# ---------------------------------------------------------------------------
puts
puts "=== End-to-End Dispatch ==="
puts "    (calling the top-confidence agent directly for each synonym query)"
puts

dispatch_results = synonym_queries.map.with_index do |q, i|
  cards = synonym_results[i][:cards]
  top   = cards.first
  next { ok: false, name: "(no match)" } unless top

  url    = top.dig("interfaces", 0, "url")
  result = A2A.client(url: url).send_task(message: A2A::Models::Message.user(q[:text]))
  reply  = result.artifacts.first&.parts&.first&.text || "(no reply)"
  conf   = top.dig("brokerMeta", "confidence")

  puts "  #{q[:label]}"
  puts "    Agent : #{top['name']} (confidence #{format('%.3f', conf)})  → #{url}"
  puts "    Reply : #{reply.lines.first&.strip}"
  puts

  { ok: result.status.state == "completed", name: top["name"] }
end

divider

# ---------------------------------------------------------------------------
# 6. Verification summary
# ---------------------------------------------------------------------------
puts
puts "=== Verification Summary ==="
puts

rfc_ok        = card_hash["name"] == "Sophisticated Broker"
synonyms_ok   = synonym_results.all? { |r| r[:pass] }
idf_ok        = idf_results.all? { |r| r[:pass] }
fallback_ok_v = fallback_ok
dispatch_ok   = dispatch_results.compact.all? { |r| r[:ok] }

puts "  Custom broker card discovered (RFC 8615)      : #{rfc_ok        ? 'PASS' : 'FAIL'}"
puts "  Synonym-expanded queries routed correctly      : #{synonyms_ok   ? 'PASS' : 'FAIL'}"
puts "  IDF-discriminating queries routed correctly    : #{idf_ok        ? 'PASS' : 'FAIL'}"
puts "  Vague query triggers fallback (≤ 2 results)   : #{fallback_ok_v ? 'PASS' : 'FAIL'}"
puts "  All top-confidence dispatch calls completed    : #{dispatch_ok   ? 'PASS' : 'FAIL'}"
puts

all_ok = rfc_ok && synonyms_ok && idf_ok && fallback_ok_v && dispatch_ok
puts(all_ok ? "All assertions passed." : "One or more assertions failed.")
