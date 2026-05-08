# frozen_string_literal: true

module A2A
  module Server
    class Base
      attr_reader :agent_card, :executor, :storage, :event_router, :push_sender

      def initialize(
        agent_card:,
        executor:,
        storage:      Storage::Memory.new,
        push_sender:  nil,
        host:         "localhost",
        port:         9292
      )
        @agent_card   = agent_card
        @executor     = executor
        @storage      = storage
        @event_router = EventRouter.new
        @push_sender  = push_sender
        @host         = host
        @port         = port
      end

      def rack_app
        klass = Class.new(App)
        klass.configure(
          agent_card:   @agent_card,
          storage:      @storage,
          executor:     @executor,
          event_router: @event_router,
          push_sender:  @push_sender
        )
        klass.freeze.app
      end

      def run
        app = rack_app
        FalconRunner.new(app, host: @host, port: @port).run
      end
    end
  end
end
