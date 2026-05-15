#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/13_custom_broker/server.rb
#
# A BrokerServer with a *custom* broker executor that replaces the default
# keyword-frequency scorer with a TF-IDF-inspired pipeline:
#
#   1. Synonym expansion   — "forex" → currency terms, "shares" → equity terms, etc.
#   2. IDF-weighted scoring — terms rare across the agent corpus score higher than
#                            terms common to many agents (inverse document frequency).
#   3. Confidence normalization — raw IDF sums rescaled to [0, 1].
#   4. Threshold filtering  — agents below MIN_CONFIDENCE are excluded from results.
#      A vague query that clears no agents' threshold falls back to the top 2.
#
# The custom executor also embeds broker metadata (confidence, matched terms) into
# each AgentCard in the result so clients can make informed dispatch decisions.
#
# Layout on http://localhost:9292 :
#   /                      → Custom Broker  (SophisticatedBrokerExecutor)
#   /.well-known/agent-card.json  → RFC 8615 broker card
#   /agents/currency       → CurrencyAgent
#   /agents/stock          → StockAgent
#   /agents/recipe         → RecipeAgent
#   /agents/trivia         → TriviaAgent
#   /agents/news           → NewsAgent

require_relative "../common_config"

BASE_URL = "http://localhost:9292"

# ---------------------------------------------------------------------------
# Sub-agent executors — lightweight mock implementations
# ---------------------------------------------------------------------------
class CurrencyExecutor < A2A::Server::AgentExecutor
  RATES = { "EUR" => 1.08, "GBP" => 1.27, "JPY" => 0.0067, "CAD" => 0.74, "AUD" => 0.65 }.freeze

  def call(ctx)
    text = ctx.message.text_content.upcase
    pair = RATES.keys.find { |c| text.include?(c) }
    if pair
      ctx.task.complete!(artifacts: [artifact("#{pair}/USD: #{RATES[pair]} (indicative rate, #{Time.now.strftime("%Y-%m-%d")})")])
    else
      lines = RATES.map { |c, r| "  #{c}/USD: #{r}" }.join("\n")
      ctx.task.complete!(artifacts: [artifact("Current indicative rates vs USD:\n#{lines}")])
    end
  end

  private

  def artifact(text)
    A2A::Models::Artifact.new(name: "exchange_rate", parts: [A2A::Models::Part.text(text)])
  end
end


class StockExecutor < A2A::Server::AgentExecutor
  QUOTES = {
    "AAPL" => { price: 189.42, change: +1.23, pct: "+0.65%" },
    "GOOG" => { price: 175.18, change: -0.87, pct: "-0.49%" },
    "MSFT" => { price: 421.75, change: +3.10, pct: "+0.74%" },
    "AMZN" => { price: 183.90, change: +0.55, pct: "+0.30%" },
    "TSLA" => { price: 177.62, change: -4.20, pct: "-2.31%" },
  }.freeze

  def call(ctx)
    text   = ctx.message.text_content.upcase
    ticker = QUOTES.keys.find { |t| text.include?(t) }
    if ticker
      q = QUOTES[ticker]
      ctx.task.complete!(artifacts: [artifact(
        "#{ticker}: $#{q[:price]}  #{q[:change] >= 0 ? "+" : ""}#{q[:change]}  (#{q[:pct]})"
      )])
    else
      lines = QUOTES.map { |t, q| "  #{t.ljust(4)} $#{q[:price]}  #{q[:pct]}" }.join("\n")
      ctx.task.complete!(artifacts: [artifact("Market snapshot:\n#{lines}")])
    end
  end

  private

  def artifact(text)
    A2A::Models::Artifact.new(name: "quote", parts: [A2A::Models::Part.text(text)])
  end
end


class RecipeExecutor < A2A::Server::AgentExecutor
  RECIPES = {
    "risotto"   => "Arborio rice, parmesan, white wine, onion, butter, stock. Toast rice, deglaze with wine, add stock ladle by ladle, finish with butter and parmesan.",
    "omelette"  => "3 eggs, butter, salt. Whisk eggs, melt butter in non-stick pan, pour eggs in, fold when just set.",
    "carbonara" => "Spaghetti, guanciale, eggs, pecorino, black pepper. Cook pasta al dente, fry guanciale, mix eggs+cheese off heat with pasta water.",
    "soup"      => "Mirepoix (onion, carrot, celery), stock, your choice of protein or vegetables. Sweat aromatics, add stock, simmer 20 min, season.",
  }.freeze

  def call(ctx)
    text   = ctx.message.text_content.downcase
    recipe = RECIPES.keys.find { |r| text.include?(r) }
    entry  = recipe ? RECIPES[recipe] : RECIPES.values.sample
    name   = recipe&.capitalize || "General recipe"
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(name: "recipe", parts: [A2A::Models::Part.text("#{name}:\n  #{entry}")])
    ])
  end
end


class TriviaExecutor < A2A::Server::AgentExecutor
  FACTS = [
    "Penicillin was discovered by Alexander Fleming in 1928.",
    "The speed of light in a vacuum is approximately 299,792,458 metres per second.",
    "The Great Wall of China is approximately 21,196 km long.",
    "Olympus Mons on Mars is the tallest volcano in the solar system at ~22 km.",
    "Shakespeare wrote 37 plays and 154 sonnets.",
    "Water freezes at 0°C (32°F) and boils at 100°C (212°F) at sea level.",
  ].freeze

  LOOKUP = {
    "penicillin" => FACTS[0], "light" => FACTS[1],  "speed" => FACTS[1],
    "wall"       => FACTS[2], "china" => FACTS[2],   "mars"  => FACTS[3],
    "volcano"    => FACTS[3], "shakespeare" => FACTS[4], "water" => FACTS[5],
  }.freeze

  def call(ctx)
    text = ctx.message.text_content.downcase
    fact = LOOKUP.find { |k, _| text.include?(k) }&.last || FACTS.sample
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(name: "fact", parts: [A2A::Models::Part.text(fact)])
    ])
  end
end


class NewsExecutor < A2A::Server::AgentExecutor
  HEADLINES = {
    "climate"    => "Global CO₂ concentration reaches record 425 ppm — scientists call for accelerated action.",
    "tech"       => "Open-source AI model outperforms proprietary counterpart on standard benchmarks.",
    "economy"    => "Central banks hold rates steady as inflation edges toward 2% target in major economies.",
    "space"      => "Next crewed lunar mission advances to final launch readiness review.",
    "health"     => "New mRNA vaccine shows 94% efficacy in phase-3 trial for respiratory pathogen.",
  }.freeze

  def call(ctx)
    text    = ctx.message.text_content.downcase
    topic   = HEADLINES.keys.find { |t| text.include?(t) }
    headline = topic ? HEADLINES[topic] : HEADLINES.values.sample
    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(name: "headline", parts: [A2A::Models::Part.text(headline)])
    ])
  end
end


# ---------------------------------------------------------------------------
# SophisticatedBrokerExecutor — TF-IDF-inspired routing with synonym expansion
# ---------------------------------------------------------------------------
class SophisticatedBrokerExecutor < A2A::Server::AgentExecutor
  # Synonyms: trigger substring → canonical terms injected into the query
  SYNONYMS = {
    "forex"    => %w[currency exchange rate],
    "fx"       => %w[currency exchange],
    "eur"      => %w[currency exchange european],
    "usd"      => %w[currency exchange dollar],
    "gbp"      => %w[currency exchange pound],
    "jpy"      => %w[currency exchange yen],
    "shares"   => %w[stock equity market],
    "equity"   => %w[stock market],
    "equities" => %w[stock market],
    "ticker"   => %w[stock quote market],
    "cook"     => %w[recipe cooking meal],
    "cooking"  => %w[recipe meal],
    "bake"     => %w[recipe cooking],
    "baking"   => %w[recipe cooking],
    "dish"     => %w[recipe meal food],
    "fact"     => %w[trivia knowledge],
    "facts"    => %w[trivia knowledge],
    "quiz"     => %w[trivia knowledge],
    "science"  => %w[trivia knowledge],
    "history"  => %w[trivia knowledge],
    "discover" => %w[trivia knowledge],
    "headline" => %w[news events current],
    "latest"   => %w[news events current],
    "today"    => %w[news events current],
    "breaking" => %w[news events current],
  }.freeze

  MIN_CONFIDENCE   = 0.20
  FALLBACK_COUNT   = 2
  MIN_TOKEN_LENGTH = 4   # short tokens cause false substring matches (e.g. "me" ⊂ "time")

  STOPWORDS = A2A::Server::BrokerExecutor::STOPWORDS

  def initialize(registry:)
    super()
    @registry = registry
    @idf      = build_idf
  end


  def call(ctx)
    keywords = expand_and_tokenize(extract_query(ctx.message))
    ranked   = rank_with_confidence(keywords)

    above    = ranked.select { |e| e[:confidence] >= MIN_CONFIDENCE }
    results  = above.empty? ? ranked.first(FALLBACK_COUNT) : above

    artifact = A2A::Models::Artifact.new(
      name: "matched_agents",
      parts: [A2A::Models::Part.json(results.map { |e|
        e[:card].to_h.merge("brokerMeta" => {
          "confidence"   => e[:confidence].round(3),
          "matchedTerms" => e[:matched_terms],
        })
      })]
    )
    ctx.task.complete!(artifacts: [artifact])
  end

  private

  def build_idf
    docs = @registry.map { |e| agent_tokens(e[:agent_card]) }
    n    = docs.size
    all_terms = docs.flatten.uniq
    all_terms.each_with_object({}) do |term, h|
      df      = docs.count { |d| d.include?(term) }
      h[term] = Math.log((n + 1.0) / (df + 1.0))  # smoothed IDF
    end
  end


  def agent_tokens(card)
    parts = [card.name, card.description.to_s]
    parts += card.skills.flat_map { |s| [s.name.to_s, s.description.to_s] }
    parts.join(" ").downcase.scan(/[a-z]+/) - STOPWORDS
  end


  def expand_and_tokenize(text)
    base = text.downcase.scan(/[a-z]+/) - STOPWORDS
    expansions = SYNONYMS.each_with_object([]) do |(trigger, additions), acc|
      acc.concat(additions) if text.downcase.include?(trigger)
    end
    (base + expansions).uniq.select { |w| w.length >= MIN_TOKEN_LENGTH }
  end


  def rank_with_confidence(keywords)
    return [] if keywords.empty?

    scored = @registry.map do |e|
      card    = e[:agent_card]
      doc     = agent_tokens(card)
      matched = keywords.select { |kw| doc.any? { |t| t.include?(kw) || kw.include?(t) } }
      score   = matched.sum { |kw| @idf.fetch(kw, Math.log((@registry.size + 1.0) / 1.0)) }
      { card: card, score: score, matched_terms: matched }
    end

    max = scored.map { |e| e[:score] }.max
    return scored.map { |e| e.merge(confidence: 0.0) } if max.nil? || max.zero?

    scored
      .map    { |e| e.merge(confidence: e[:score] / max) }
      .sort_by { |e| -e[:confidence] }
  end


  def extract_query(message)
    return "" unless message

    message.parts.filter_map(&:text).join(" ")
  end
end


# ---------------------------------------------------------------------------
# Agent cards
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

currency_card = agent_card(
  name:        "CurrencyAgent",
  description: "Provides live foreign exchange rates and currency conversion between major pairs",
  skills:      [
    { name: "exchange rate",     desc: "Current spot rate between currency pairs"      },
    { name: "forex conversion",  desc: "Convert an amount from one currency to another" },
    { name: "currency pairs",    desc: "Rates for EUR, GBP, JPY, CAD, AUD vs USD"      },
  ],
  path:        "/agents/currency"
)

stock_card = agent_card(
  name:        "StockAgent",
  description: "Delivers real-time stock quotes and equity market analysis for major tickers",
  skills:      [
    { name: "stock quote",     desc: "Current price, change, and percent move for a ticker" },
    { name: "market analysis", desc: "Sector trends and market-wide snapshot"                },
    { name: "equity research", desc: "Fundamental and technical notes for listed companies"  },
  ],
  path:        "/agents/stock"
)

recipe_card = agent_card(
  name:        "RecipeAgent",
  description: "Finds recipes, lists ingredients, and gives step-by-step cooking instructions",
  skills:      [
    { name: "recipe search",  desc: "Find a recipe by dish name: risotto, carbonara, pasta" },
    { name: "ingredient list", desc: "Full ingredient list with quantities"          },
    { name: "meal planning",  desc: "Suggest meals for a week based on preferences" },
  ],
  path:        "/agents/recipe"
)

trivia_card = agent_card(
  name:        "TriviaAgent",
  description: "Answers factual questions spanning history, science, geography, and culture",
  skills:      [
    { name: "general knowledge", desc: "Answers to factual questions on any topic" },
    { name: "historical facts",  desc: "Dates, people, and events in world history" },
    { name: "science trivia",    desc: "Physics, biology, chemistry, and astronomy facts" },
  ],
  path:        "/agents/trivia"
)

news_card = agent_card(
  name:        "NewsAgent",
  description: "Delivers current events and breaking news headlines across topics",
  skills:      [
    { name: "current events", desc: "Latest news stories and developments"       },
    { name: "news headlines", desc: "Top headlines by topic: tech, climate, etc." },
    { name: "topic summary",  desc: "Brief summary of a news topic or story"     },
  ],
  path:        "/agents/news"
)

# ---------------------------------------------------------------------------
# Build the registry first so the custom executor can pre-compute IDF weights
# ---------------------------------------------------------------------------
agents = {
  "/agents/currency" => { agent_card: currency_card, executor: CurrencyExecutor.new },
  "/agents/stock"    => { agent_card: stock_card,    executor: StockExecutor.new    },
  "/agents/recipe"   => { agent_card: recipe_card,   executor: RecipeExecutor.new   },
  "/agents/trivia"   => { agent_card: trivia_card,   executor: TriviaExecutor.new   },
  "/agents/news"     => { agent_card: news_card,     executor: NewsExecutor.new     },
}

# Mirror the registry format that BrokerServer uses internally
registry = agents.map { |path, cfg| { agent_card: cfg[:agent_card], url: path } }

custom_executor = SophisticatedBrokerExecutor.new(registry: registry)

broker_card = A2A::Models::AgentCard.new(
  name:         "Sophisticated Broker",
  description:  "TF-IDF-ranked broker with synonym expansion and confidence thresholding",
  version:      "1.0.0",
  capabilities: A2A::Models::AgentCapabilities.new,
  interfaces:   [],
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "IDF-ranked routing",
      description: "Scores agents by inverse document frequency so discriminating terms outweigh common ones"
    ),
    A2A::Models::AgentSkill.new(
      name:        "synonym expansion",
      description: "Expands domain synonyms (forex, equity, cook…) before scoring to improve recall"
    ),
  ]
)

# ---------------------------------------------------------------------------
# Start the server
# ---------------------------------------------------------------------------
puts "Starting custom broker on #{BASE_URL}"
puts
puts "  /                           → Sophisticated Broker (IDF + synonyms)"
puts "  /.well-known/agent-card.json→ RFC 8615 discovery endpoint"
puts "  /agents/currency            → CurrencyAgent"
puts "  /agents/stock               → StockAgent"
puts "  /agents/recipe              → RecipeAgent"
puts "  /agents/trivia              → TriviaAgent"
puts "  /agents/news                → NewsAgent"
puts
puts "Press Ctrl-C to stop."
puts

A2A.broker_server(
  agents:          agents,
  broker_card:     broker_card,
  broker_executor: custom_executor,
  port:            9292
).run
