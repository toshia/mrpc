# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    class SpellRequester
      AWAIT_REQUEST = 0

      attr_reader :send_queue

      def initialize(receive)
        @receive = receive
        @send_queue = Queue.new
        @awaiting = {} # Integer id => Queue awaiting
        start_read
      end

      def start_read
        @read_thread ||= Thread.new do
          @receive.each do |payload|
            notice payload # <Mrpc::SpellRequest: request: <Mrpc::SpellRequest::Call: name: "compose", models: [<Mrpc::Proxy: class_id: "Plugin::Mastodon::World", id: "plugin://world.mastodon/social.mikutter.hachune.net/toshi_a">], params: {"body"=><Mrpc::Param: sval: "mrpc">}>>
            case payload.payload
            when :request
              notice 'receive request!!!'
              receive_request(payload.request)
            when :resolve
              notice 'receive resolve!!!'
              receive_resolve(payload.resolve)
            else
              error 'does not match!'
              error payload.payload
            end
            notice 'spell received. waiting next message...'
          end
        rescue => err
          error err
        ensure
          notice 'spell receive finish.'
        end
      end

      # rpc Spell(SpellRequest) returns (SpellResponse);
      def each_item
        return enum_for(:each_item) unless block_given?
        begin
          notice 'start!'
          loop do
            message = send_queue.pop
            yield message
            break if [:ok, :ng].include?(message.payload)
          end
          notice 'spell send finish normally.'
        rescue StandardError => e
          error e
          fail e # signal completion via an error
        ensure
          @read_thread&.kill
          warn 'spell end!'
        end
      end

      private

      # @param [Mrpc::SpellRequest::Call] request
      def receive_request(request)
        proxies = request.models.map do |proxy|
          Plugin::RemotePluginCall::ProxyObject.new(proxy, method(:proxy_resolver))
        end
        # notice proxies
        plugin.spell(request.name.to_sym, *proxies, request.params.to_h).next { |result|
          notice result
          @send_queue.push(
            ::Mrpc::SpellResponse.new(
              ok: ::Mrpc::SpellResponse::Success.new(
                value: ::Plugin::RemotePluginCall.mrpc_param(result)
              )
            )
          )
        }.trap { |err|
          warn err
          @send_queue.push(
            ::Mrpc::SpellResponse.new(
              ng: ::Mrpc::SpellResponse::Error.new(
                value: ::Plugin::RemotePluginCall.mrpc_param(err)
              )
            )
          )
        }.terminate
      end

      # @param [Mrpc::ProxyValue] resolve
      def receive_resolve(resolve)
        query_id = resolve.subject&.class_id.hash ^ resolve.subject&.id.hash ^ resolve.selection.hash
        @awaiting.fetch(query_id).push(resolve)
        @awaiting.delete(query_id)
      end

      # @return [::Mrpc::ProxyParam]
      def send_query(subject:, selection:)
        query_id = subject.class_id.hash ^ subject.id.hash ^ selection.hash
        await = @awaiting[query_id] = Queue.new
        ::Mrpc::FilteringRequest.new(
          query: ::Mrpc::ProxyQuery.new(
            subject: subject,
            selection: selection,
          )
        )
        msg = ::Mrpc::SpellResponse.new(
          query: {
            subject: subject,
            selection: selection
          }
        )
        notice 'send_query!'
        notice msg
        @send_queue.push(
          msg
        )
        await.pop.response
      end

      def proxy_resolver(proxy_object, message)
        param = send_query(
          subject: proxy_object.proxy,
          selection: message.to_s
        )
        if param.val != :error
          Plugin::RemotePluginCall.mrpc_param_unbox(param, method(:proxy_resolver))
        else
          raise param.error
        end
      end

      def plugin
        Plugin[:mrpc]
      end
    end
  end
end
