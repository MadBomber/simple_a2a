#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/09_multipart/server.rb
#
# Demonstrates all four Part types in a single artifact:
#
#   Part.text      — plain prose summary
#   Part.json      — structured metadata as a Ruby hash
#   Part.binary    — raw bytes (a CSV here), base64-encoded in transit
#   Part.from_url  — a URL reference to an external resource
#
# The agent treats any input as a topic and fabricates a four-part
# report artifact so the client can exercise every Part type.

require_relative "../common_config"

class ReportExecutor < A2A::Server::AgentExecutor
  def call(ctx)
    topic = ctx.message.text_content.strip
    topic = "unknown topic" if topic.empty?

    # Part 1 — prose summary
    summary = A2A::Models::Part.text(<<~TEXT.strip, media_type: "text/plain")
      Report on: #{topic}
      Generated at #{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}

      This is a synthetic report for demonstration purposes. In a real agent,
      this section would contain the executive summary of the analysis.
    TEXT

    # Part 2 — structured JSON metadata
    metadata = A2A::Models::Part.json(
      {
        "topic"      => topic,
        "word_count" => topic.split.length,
        "tags"       => topic.downcase.split.first(3),
        "confidence" => 0.92,
        "generated"  => true
      },
      filename: "metadata.json"
    )

    # Part 3 — binary blob (a tiny CSV), base64-encoded in transit
    csv_rows  = [["rank", "term", "score"]] +
                topic.split.first(5).each_with_index.map { |w, i| [i + 1, w, (0.9 - i * 0.1).round(2)] }
    csv_bytes = csv_rows.map { |row| row.join(",") }.join("\n").b

    csv_part = A2A::Models::Part.binary(
      csv_bytes,
      media_type: "text/csv",
      filename:   "term_scores.csv"
    )

    # Part 4 — URL reference to a related external resource
    search_url = "https://en.wikipedia.org/wiki/Special:Search?search=#{URI.encode_uri_component(topic)}"
    url_part   = A2A::Models::Part.from_url(
      search_url,
      media_type: "text/html",
      filename:   "reference.html"
    )

    ctx.task.complete!(artifacts: [
      A2A::Models::Artifact.new(
        name:  "report",
        parts: [summary, metadata, csv_part, url_part]
      )
    ])
  end
end

card = A2A::Models::AgentCard.new(
  name:         "ReportAgent",
  version:      "1.0",
  description:  "Returns a four-part artifact: text summary, JSON metadata, binary CSV, and a URL reference",
  capabilities: A2A::Models::AgentCapabilities.new,
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "report",
      description: "Generates a multi-part report artifact for any topic"
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
  Starting ReportAgent on http://localhost:9292
  Returns a 4-part artifact (text + JSON + binary + URL) for any topic.
  Press Ctrl-C to stop.

HEREDOC

A2A.server(agent_card: card, executor: ReportExecutor.new).run
