# frozen_string_literal: true

require "rack"

module A2A
  module Server
    # Hosts multiple A2A agents on a single server, each at its own URL path.
    #
    # Usage:
    #   A2A.multi_server(
    #     agents: {
    #       "/anthropic" => { agent_card: card1, executor: exec1 },
    #       "/openai"    => { agent_card: card2, executor: exec2 }
    #     },
    #     port: 9292
    #   ).run
    class MultiAgent
      def initialize(agents:, host: "localhost", port: 9292)
        @agents = agents
        @host   = host
        @port   = port
      end


      def run
        FalconRunner.new(rack_app, host: @host, port: @port).run
      end

      private

      def rack_app
        url_map = @agents.transform_values { |cfg| build_app(cfg) }
        Rack::URLMap.new(url_map)
      end


      # Each agent needs its own App subclass so class-level configure state
      # doesn't bleed between agents.
      def build_app(cfg)
        klass = Class.new(App)
        klass.configure(
          agent_card: cfg[:agent_card],
          storage: cfg[:storage] || Storage::Memory.new,
          executor: cfg[:executor],
          broadcast_registry: BroadcastRegistry.new,
          push_sender: cfg[:push_sender]
        )
        klass.freeze.app
      end
    end
  end
end
