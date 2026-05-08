# frozen_string_literal: true

module A2A
  module Models
    class StreamResponse < Base
      attribute :task
      attribute :message
      attribute :status_update
      attribute :artifact_update

      def task?            = !task.nil?
      def message?         = !message.nil?
      def status_update?   = !status_update.nil?
      def artifact_update? = !artifact_update.nil?

      def self.from_hash(hash)
        return nil if hash.nil?
        if hash["task"]
          new(task: Task.from_hash(hash["task"]))
        elsif hash["message"]
          new(message: Message.from_hash(hash["message"]))
        elsif hash["statusUpdate"]
          new(status_update: hash["statusUpdate"])
        elsif hash["artifactUpdate"]
          new(artifact_update: hash["artifactUpdate"])
        else
          new
        end
      end
    end
  end
end
