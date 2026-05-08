# frozen_string_literal: true

require "falcon"
require "async"
require "async/http/endpoint"

module A2A
  module Server
    class FalconRunner
      DEFAULT_HOST = "localhost"
      DEFAULT_PORT = 9292

      def initialize(app, host: DEFAULT_HOST, port: DEFAULT_PORT)
        @app  = app
        @host = host
        @port = port
      end

      def run
        endpoint = Async::HTTP::Endpoint.parse("http://#{@host}:#{@port}")
        server   = Falcon::Server.new(Falcon::Server.middleware(@app), endpoint)

        Async do
          server.run
        end
      end
    end
  end
end
