# frozen_string_literal: true

module A2A
  module Server
    class ResumeContext < Context
      attr_reader :resume_message

      def initialize(resume_message:, **kwargs)
        super(**kwargs)
        @resume_message = resume_message
      end
    end
  end
end
