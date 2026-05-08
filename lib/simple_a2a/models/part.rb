# frozen_string_literal: true

module A2A
  module Models
    class Part < Base
      attribute :text
      attribute :raw
      attribute :url
      attribute :data
      attribute :media_type
      attribute :filename
      attribute :metadata

      def self.text(content, media_type: "text/plain", filename: nil)
        new(text: content, media_type: media_type, filename: filename)
      end

      def self.json(hash, filename: nil)
        new(data: hash, media_type: "application/json", filename: filename)
      end

      def self.from_url(url, media_type:, filename: nil)
        new(url: url, media_type: media_type, filename: filename)
      end

      def self.binary(bytes, media_type:, filename: nil)
        new(raw: Base64.strict_encode64(bytes), media_type: media_type, filename: filename)
      end

      def text?  = !text.nil?
      def json?  = !data.nil?
      def url?   = !url.nil?
      def raw?   = !raw.nil?

      def decoded_bytes
        return nil unless raw
        Base64.strict_decode64(raw)
      end

      def valid?
        [text, raw, url, data].compact.length == 1
      end
    end
  end
end
