# frozen_string_literal: true

require "digest"
require "jwt"
require "net/http"
require "uri"

module A2A
  module Server
    class PushSender
      SUPPORTED_SCHEMES = %w[bearer token].freeze

      def initialize(private_key: nil, key_id: nil, issuer: "simple_a2a")
        @private_key = private_key
        @key_id      = key_id
        @issuer      = issuer
      end

      def deliver(config, event)
        return unless config.is_a?(Models::PushNotificationConfig)
        return unless config.valid?

        payload = build_payload(event)
        headers = build_headers(config, payload)
        post(config.webhook_url, payload, headers)
      rescue StandardError => e
        A2A.logger&.warn("PushSender: delivery failed to #{config&.webhook_url} — #{e.class}: #{e.message}")
        false
      end

      private

      def build_payload(event)
        JSON.generate(event.to_h)
      end

      def build_headers(config, payload)
        headers = { "Content-Type" => "application/json" }
        auth = config.authentication_info
        return headers unless auth

        case auth.scheme.to_s.downcase
        when "bearer"
          token = jwt_token(payload)
          headers[auth.header_name || "Authorization"] = "Bearer #{token}"
        when "token"
          headers[auth.header_name || "Authorization"] = "Token #{auth.value}"
        else
          headers[auth.header_name || "Authorization"] = auth.value
        end

        headers
      end

      def jwt_token(payload)
        return "no-key" unless @private_key

        claims = {
          iss: @issuer,
          iat: Time.now.to_i,
          exp: Time.now.to_i + 300,
          payload_hash: Digest::SHA256.hexdigest(payload)
        }
        JWT.encode(claims, @private_key, "RS256", { kid: @key_id }.compact)
      end

      def post(url, body, headers)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = body
        response = http.request(request)
        response.code.to_i < 300
      end
    end
  end
end
