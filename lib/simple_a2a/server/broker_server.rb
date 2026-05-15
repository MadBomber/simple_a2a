# frozen_string_literal: true

require "rack"

module A2A
  module Server
    # Hosts a broker agent at the server root plus multiple sub-agents at
    # path prefixes. The broker occupies GET /.well-known/agent-card.json
    # (RFC 8615 compliant) and handles task requests by evaluating them
    # against registered sub-agents and returning a ranked array of
    # matching AgentCards as a task artifact.
    #
    # Usage:
    #   A2A.broker_server(
    #     agents: {
    #       "/agents/weather" => { agent_card: card1, executor: exec1 },
    #       "/agents/billing" => { agent_card: card2, executor: exec2 }
    #     },
    #     broker_card:     nil,   # optional — auto-generated if omitted
    #     broker_executor: nil,   # optional — BrokerExecutor used if omitted
    #     host: "localhost",
    #     port: 9292
    #   ).run
    #
    # Replacement levels:
    #   Neither param     — default card + default BrokerExecutor
    #   broker_executor:  — custom logic, auto-generated card
    #   both params       — fully custom broker
    class BrokerServer
      DEFAULT_BROKER_SKILL = Models::AgentSkill.new(
        name: "Agent Matcher",
        description: "Evaluates a service request and returns a ranked array of matching agent cards."
      ).freeze

      def initialize(agents:, broker_card: nil, broker_executor: nil, host: "localhost", port: 9292)
        @agents          = agents
        @broker_card     = broker_card
        @broker_executor = broker_executor
        @host            = host
        @port            = port
      end


      def rack_app
        registry = build_registry
        executor = @broker_executor || BrokerExecutor.new(registry: registry)
        card     = @broker_card     || default_broker_card

        url_map = { "/" => build_app(card, executor) }
        @agents.each { |path, cfg| url_map[path] = build_app(cfg[:agent_card], cfg[:executor], cfg: cfg) }

        Rack::URLMap.new(url_map)
      end


      def run
        FalconRunner.new(rack_app, host: @host, port: @port).run
      end

      private

      def build_registry
        @agents.map { |path, cfg| { agent_card: cfg[:agent_card], url: path } }
      end


      def default_broker_card
        Models::AgentCard.new(
          name: "Service Broker",
          description: "Evaluates service requests and returns ranked agent cards " \
                       "for agents hosted on this server.",
          version: "1.0.0",
          capabilities: Models::AgentCapabilities.new,
          interfaces: [],
          skills: [DEFAULT_BROKER_SKILL]
        )
      end


      def build_app(card, executor, cfg: {})
        klass = Class.new(App)
        klass.configure(
          agent_card: card,
          storage: cfg[:storage] || Storage::Memory.new,
          executor: executor,
          broadcast_registry: BroadcastRegistry.new,
          push_sender: cfg[:push_sender]
        )
        klass.freeze.app
      end
    end
  end
end
