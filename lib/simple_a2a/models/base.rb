# frozen_string_literal: true

module SimpleA2a
  module Models
    class Base
      class << self
        def attribute(name, type: nil, default: nil, required: false)
          attributes[name] = { type: type, default: default, required: required }
          attr_accessor name
        end

        def attributes
          @attributes ||= {}
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@attributes, attributes.dup)
        end

        def from_hash(hash)
          return nil if hash.nil?
          kwargs = {}
          attributes.each do |name, opts|
            val = find_value(hash, name)
            next if val.nil?
            kwargs[name] = coerce(val, opts[:type])
          end
          new(**kwargs)
        end

        private

        def find_value(hash, name)
          camel = camelize(name)
          hash[camel] || hash[camel.to_sym] || hash[name.to_s] || hash[name]
        end

        def camelize(snake)
          parts = snake.to_s.split("_")
          (parts[0..0] + parts[1..].map(&:capitalize)).join
        end

        def coerce(val, type)
          return val if type.nil?

          if type.is_a?(Array)
            item_type = type[0]
            return val unless val.is_a?(Array)
            return val.map { |v| coerce(v, item_type) }
          end

          return val if val.is_a?(type)
          return type.from_hash(val) if val.is_a?(Hash) && type.respond_to?(:from_hash)
          val
        end
      end

      def initialize(**kwargs)
        self.class.attributes.each do |name, opts|
          val = kwargs.key?(name) ? kwargs[name] : resolve_default(opts[:default])
          send(:"#{name}=", val)
        end
      end

      def to_h
        self.class.attributes.each_with_object({}) do |(name, _), result|
          val = send(name)
          next if val.nil?
          result[camelize(name)] = serialize(val)
        end
      end

      def to_json(*)
        JSON.generate(to_h)
      end

      def valid?
        self.class.attributes.all? do |name, opts|
          !opts[:required] || !send(name).nil?
        end
      end

      def ==(other)
        return false unless other.is_a?(self.class)
        self.class.attributes.keys.all? { |n| send(n) == other.send(n) }
      end

      private

      def camelize(snake)
        parts = snake.to_s.split("_")
        (parts[0..0] + parts[1..].map(&:capitalize)).join
      end

      def resolve_default(default)
        default.respond_to?(:call) ? default.call : default
      end

      def serialize(val)
        case val
        when Base  then val.to_h
        when Array then val.map { |v| serialize(v) }
        when Hash  then val.transform_values { |v| serialize(v) }
        when Time  then val.iso8601
        else            val
        end
      end
    end
  end
end
