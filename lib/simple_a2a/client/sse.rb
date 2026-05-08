# frozen_string_literal: true

module A2A
  module Client
    class SSE < Base
      EVENT_CLASSES = {
        "TaskStatusUpdateEvent"   => Models::TaskStatusUpdateEvent,
        "TaskArtifactUpdateEvent" => Models::TaskArtifactUpdateEvent
      }.freeze

      def send_subscribe(message:, **opts, &block)
        body = JSON.generate({
          "jsonrpc" => "2.0",
          "id"      => SecureRandom.uuid,
          "method"  => "tasks/sendSubscribe",
          "params"  => build_send_params(message, opts)
        })

        run_async do |internet|
          headers  = rpc_headers.merge("accept" => "text/event-stream")
          response = internet.post(@url, headers: headers, body: body)
          parse_sse_stream(response, &block)
        end
      end

      private

      def parse_sse_stream(response, &block)
        buffer = +""
        response.body.each do |chunk|
          buffer << chunk
          while (idx = buffer.index("\n\n"))
            event_str = buffer[0, idx]
            buffer    = buffer[(idx + 2)..]
            event     = parse_sse_event(event_str)
            block.call(event) if event
          end
        end
      end

      def parse_sse_event(event_str)
        data = nil
        event_str.each_line do |line|
          data = line.chomp[6..] if line.start_with?("data: ")
        end
        return nil unless data

        parsed    = JSON.parse(data)
        result    = parsed["result"] || parsed
        type_name = result["type"] || result["kind"]
        klass     = EVENT_CLASSES[type_name]
        klass ? klass.from_hash(result) : result
      rescue JSON::ParserError
        nil
      end
    end
  end
end
