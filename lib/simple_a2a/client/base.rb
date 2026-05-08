# frozen_string_literal: true

require "async"
require "async/http/internet"

module A2A
  module Client
    class Base
      def initialize(url:, headers: {})
        @url     = url
        @headers = headers
      end

      def agent_card
        body = http_get("agentCard")
        Models::AgentCard.from_hash(JSON.parse(body))
      end

      def send_task(message:, **opts)
        result = rpc_call("tasks/send", build_send_params(message, opts))
        Models::Task.from_hash(result)
      end

      def get_task(task_id)
        result = rpc_call("tasks/get", { "id" => task_id })
        Models::Task.from_hash(result)
      end

      def list_tasks
        result = rpc_call("tasks/list", {})
        result.map { |t| Models::Task.from_hash(t) }
      end

      def cancel_task(task_id)
        result = rpc_call("tasks/cancel", { "id" => task_id })
        Models::Task.from_hash(result)
      end

      private

      def rpc_call(method, params)
        body = JSON.generate({
          "jsonrpc" => "2.0",
          "id"      => SecureRandom.uuid,
          "method"  => method,
          "params"  => params
        })
        resp_body = http_post(body)
        parsed    = JSON.parse(resp_body)
        raise A2A::Error, parsed["error"]["message"] if parsed["error"]

        parsed["result"]
      end

      def http_post(body)
        run_async do |internet|
          internet.post(@url, headers: rpc_headers, body: body).read
        end
      end

      def http_get(path)
        url = [@url.chomp("/"), path].join("/")
        run_async do |internet|
          internet.get(url, headers: extra_headers).read
        end
      end

      def run_async(&block)
        if Async::Task.current?
          with_internet(&block)
        else
          Async { with_internet(&block) }.wait
        end
      end

      def with_internet
        internet = Async::HTTP::Internet.new
        yield internet
      ensure
        internet&.close
      end

      def rpc_headers
        { "content-type" => "application/json" }.merge(extra_headers)
      end

      def extra_headers
        @headers.transform_keys(&:to_s).transform_values(&:to_s)
      end

      def build_send_params(message, opts)
        msg_hash = message.is_a?(Models::Message) ? message.to_h : message
        params   = { "message" => msg_hash }
        params["id"]        = opts[:task_id]    if opts[:task_id]
        params["contextId"] = opts[:context_id] if opts[:context_id]
        params["metadata"]  = opts[:metadata]   if opts[:metadata]
        params
      end
    end
  end
end
