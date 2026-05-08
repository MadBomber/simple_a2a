# frozen_string_literal: true

module A2A
  module Storage
    class Base
      def save(task)    = raise NotImplementedError, "#{self.class}#save"
      def find(id)      = raise NotImplementedError, "#{self.class}#find"
      def delete(id)    = raise NotImplementedError, "#{self.class}#delete"
      def list          = raise NotImplementedError, "#{self.class}#list"
    end
  end
end
