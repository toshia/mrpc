# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    class Server < ::Mrpc::PluggaloidService::Service
      # rpc Query(ProxyQuery) returns (ProxyValue);
      # @params q ::Mrpc::ProxyQuery
      def query(q, _call)
        notice q # <Mrpc::ProxyQuery: selection: "">
        method = q.selection
        value = Pluggaloid::Mirage.unwrap(namespace: q.subject.class_id, id: q.subject.id)
        ::Mrpc::ProxyValue.new(
          subject: q.subject,
          selection: q.selection,
          response: Plugin::RemotePluginCall.mrpc_param(value.public_send(method))
        )
      rescue => err
        error err
        raise
      end

      def subscribe(request, _call)
        queue = Queue.new
        Plugin[:remote_plugin_call].add_event(request.name) do |*args|
          queue.push ::Mrpc::Event.new(
            name: request.name,
            param: args.map{ |a| Plugin::RemotePluginCall.mrpc_param(a) }
          )
        end
        Enumerator.new do |y|
          loop do
            y << queue.pop
          end
        end
      rescue => err
        error err
        raise
      end

      def filtering(request, _call)
        FilteringRequester.new(request).each_item
      rescue => err
        error err
        raise
      end

      def spell(request, _call)
        notice request
        ::Plugin::RemotePluginCall::SpellRequester.new(request).each_item
      rescue => err
        error err
        raise
      end
    end
  end
end
