# frozen_string_literal: true

module A2A
  module Server
    module PushHandlers
      private

      def push_guard!
        return if self.class.agent_card&.capabilities&.push_notifications

        raise PushNotificationNotSupportedError
      end


      def build_push_config!(cfg_h, task_id)
        raise JsonRpc::InvalidParamsError, "pushNotificationConfig is required" unless cfg_h.is_a?(Hash)

        config = Models::PushNotificationConfig.from_hash(cfg_h.merge("taskId" => task_id))
        unless config.valid?
          raise JsonRpc::InvalidParamsError,
                "pushNotificationConfig.webhookUrl is required"
        end

        config
      end


      def handle_push_set(rpc_req)
        push_guard!
        params  = rpc_req.params || {}
        task_id = params["id"] or raise JsonRpc::InvalidParamsError, "id is required"
        config  = build_push_config!(params["pushNotificationConfig"], task_id)
        self.class.storage.find!(task_id)
        self.class.push_config_store.set(task_id, config)
        result = { "id" => task_id, "pushNotificationConfig" => config.to_h }
        JsonRpc::Response.success(id: rpc_req.id, result: result)
      end


      def handle_push_get(rpc_req)
        push_guard!
        params  = rpc_req.params || {}
        task_id = params["id"] or raise JsonRpc::InvalidParamsError, "id is required"
        config  = self.class.push_config_store.get(task_id)
        result  = config ? { "id" => task_id, "pushNotificationConfig" => config.to_h } : nil
        JsonRpc::Response.success(id: rpc_req.id, result: result)
      end


      def handle_push_delete(rpc_req)
        push_guard!
        params  = rpc_req.params || {}
        task_id = params["id"] or raise JsonRpc::InvalidParamsError, "id is required"
        self.class.push_config_store.delete(task_id)
        JsonRpc::Response.success(id: rpc_req.id, result: nil)
      end


      def handle_push_list(rpc_req)
        push_guard!
        configs = self.class.push_config_store.list
        result  = configs.map { |tid, cfg| { "id" => tid, "pushNotificationConfig" => cfg.to_h } }
        JsonRpc::Response.success(id: rpc_req.id, result: result)
      end
    end
  end
end
