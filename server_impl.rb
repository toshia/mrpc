# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    class Server < ::Mrpc::PluggaloidService::Service
      # @params q ::Mrpc::ProxyValue
      def query(q, _call)
        method = q.selection
        value = Plugin::RemotePluginCall::Proxy.unwrap(q.subject)
        ::Mrpc::ProxyValue.new(
          subject: q.subject,
          selection: q.selection,
          response: Plugin::RemotePluginCall.mrpc_param(value.public_send(method))
        )
      end

      def subscribe(request, _call)
        queue = Queue.new
        Plugin[:remote_plugin_call].add_event(request.name) do |*args|
          queue.push ::Mrpc::Event.new(
            name: request.name,
            #param: args.map(&Plugin::RemotePluginCall.method(:mrpc_param))
            param: args.map{ |a| Plugin::RemotePluginCall.mrpc_param(a) }
          )
        end
        Enumerator.new do |y|
          loop do
            y << queue.pop
          end
        end
      end

      def filtering(request, _call)
        request_sender = FilteringRequestSender.new
        filter_response_queue = Queue.new # Mrpc::FilterQuery
        filter = nil
        event_id = 0

        request.each do |filtering_payload|
          notice "receive: #{filtering_payload.inspect}"
          if filtering_payload.has_start?
            filter = filtering_start(filtering_payload.start.name.freeze, filter_response_queue, request_sender)
          elsif filtering_payload.has_response?
            response = filtering_payload.response
            if response.event_id == event_id
              filter_response_queue.push(response)
            else
              warn "event_id mismatched! (expect #{event_id}, actual #{response.event_id} in `#{filter.name}')"
            end
          elsif filtering_payload.has_resolve?
            request_sender.resolve(filtering_payload.resolve)
          end
        rescue StandardError => e
          error e
        ensure
          warn "#{filter&.name} closed!!!"
          filter_response_queue.close
          request_sender.close
          Plugin[:remote_plugin_call].detach(filter) if filter
        end
        Enumerator.new do |yielder|
          a = request_sender.queue.pop
          event_id = a.event_id
          notice "send #{a.inspect}"
          yielder << a
          notice "#{filter&.name} closed normally"
        end
      end

      # @params [String|Symbol] filter_name フィルタ名
      # @params [Queue.new<Mrpc::FilterQuery>] iqueue クライアントからのレスポンス
      # @params [Queue.new<Mrpc::FilterQuery>] oqueue サーバからのリクエスト
      def filtering_start(filter_name, filter_response_queue, sender, &gen_event_id)
        Plugin[:remote_plugin_call].add_event_filter(filter_name) do |*args|
          event_id = SecureRandom.random_number(1 << 64)
          sender.request(
            ::Mrpc::FilterQuery.new(
              name: filter_name,
              event_id: event_id,
              param: args.map(&Plugin::RemotePluginCall.method(:mrpc_param))))
          filter_query = filter_response_queue.pop
          notice "response: #{filter_query}"
          if filter_query&.event_id == event_id
            filter_query.param.map do |param|
              Plugin::RemotePluginCall.mrpc_param_unbox(
                param, ->(proxy_object, message) { # ::Mrpc::Proxy
                  sender.query(
                    target: proxy_object,
                    selection: message
                  )
                  # queue = Queue.new # Mrpc::Param
                  # query_resolve_queue.push({proxy: box, notify_to: queue})
                  # Plugin::RemotePluginCall.mrpc_param_unbox(queue.pop)
                }
              )
            end
          end
        end
      end
    end
  end
end
