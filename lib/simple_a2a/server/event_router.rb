# frozen_string_literal: true

require "typed_bus"

module A2A
  module Server
    class EventRouter
      def initialize
        @bus = TypedBus::MessageBus.new
      end

      def open(task_id)
        return if @bus.channel?(task_id.to_sym)
        @bus.add_channel(task_id.to_sym, type: nil, timeout: nil)
      end

      def close(task_id)
        @bus.remove_channel(task_id.to_sym)
      end

      def publish(task_id, event)
        sym = task_id.to_sym
        open(task_id) unless @bus.channel?(sym)
        @bus.publish(sym, event)
      rescue ArgumentError
        nil
      end

      def subscribe(task_id, &block)
        sym = task_id.to_sym
        open(task_id) unless @bus.channel?(sym)
        @bus.subscribe(sym) do |delivery|
          block.call(delivery.message)
          delivery.ack!
        end
      end

      def unsubscribe(task_id, id_or_block)
        return unless @bus.channel?(task_id.to_sym)
        @bus.unsubscribe(task_id.to_sym, id_or_block)
      rescue ArgumentError
        nil
      end

      def channel?(task_id)
        @bus.channel?(task_id.to_sym)
      end
    end
  end
end
