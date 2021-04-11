# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    class Server < ::Mrpc::PluggaloidService::Service
      # @params q ::Mrpc::ProxyValue
      def query(q, _call)
        method = q.selection
        value = Pluggaloid::Mirage.unwrap(namespace: q.subject.class_id, id: q.subject.id)
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
        FilteringRequester.new(request).each_item
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
