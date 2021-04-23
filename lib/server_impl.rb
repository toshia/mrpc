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
