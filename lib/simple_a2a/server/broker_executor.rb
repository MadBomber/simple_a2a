# frozen_string_literal: true

module A2A
  module Server
    # Default broker implementation. Scores registered sub-agents against
    # the text of the incoming message and returns a ranked JSON array of
    # matching AgentCards as a task artifact.
    #
    # Scoring weights (per keyword hit):
    #   skill name words  — 0.75
    #   agent name words  — 0.50
    #   description words — 0.25 (exact match only)
    #
    # Replace with a custom executor by passing broker_executor: to BrokerServer.
    class BrokerExecutor < AgentExecutor
      STOPWORDS = %w[
        a an the is are was were be been being have has had do does did
        will would could should may might shall can i you he she it we
        they what which who whom this that these those am for of to in
        on at by with from and or but not
      ].freeze

      def initialize(registry:)
        super()
        @registry = registry  # Array of { agent_card:, url: }
      end


      def call(ctx)
        keywords = tokenize(extract_query(ctx.message))
        ranked   = rank_agents(keywords)
        artifact = Models::Artifact.new(
          name: "matched_agents",
          parts: [Models::Part.json(ranked.map(&:to_h))]
        )
        ctx.task.complete!(artifacts: [artifact])
      end

      private

      def rank_agents(keywords)
        return @registry.map { |e| e[:agent_card] } if keywords.empty?

        @registry
          .map    { |e| [score(e[:agent_card], keywords), e[:agent_card]] }
          .select { |s, _| s.positive? }
          .sort_by { |s, _| -s }
          .map { |_, card| card }
      end


      def score(card, keywords)
        skill_score(card, keywords) + name_score(card, keywords) + description_score(card, keywords)
      end


      def skill_score(card, keywords)
        skill_words = card.skills.flat_map { |s| tokenize(s.name) }
        keywords.sum { |kw| skill_words.any? { |w| w.include?(kw) || kw.include?(w) } ? 0.75 : 0.0 }
      end


      def name_score(card, keywords)
        name_words = tokenize(card.name)
        keywords.sum { |kw| name_words.any? { |w| w.include?(kw) || kw.include?(w) } ? 0.5 : 0.0 }
      end


      def description_score(card, keywords)
        desc_words = tokenize(card.description.to_s)
        keywords.sum { |kw| desc_words.include?(kw) ? 0.25 : 0.0 }
      end


      def extract_query(message)
        return "" unless message

        message.parts.filter_map(&:text).join(" ")
      end


      def tokenize(text)
        text.to_s.downcase.scan(/[a-z]+/) - STOPWORDS
      end
    end
  end
end
