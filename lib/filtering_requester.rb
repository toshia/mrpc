# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    class FilteringRequester
      attr_reader :send_queue

      def initialize(receive)
        @receive = receive
        @tag = plugin.handler_tag
        @send_queue = Queue.new
        @awaiting = {} # Integer id => Queue awaiting
      end

      # rpc Filtering(stream FilteringPayload) returns (stream FilteringRequest);
      def each_item
        return enum_for(:each_item) unless block_given?
        begin
          notice 'start!'
          @receive.each do |payload|
            notice payload
            case
            when payload.has_start?
              receive_start(payload.start)
            when payload.has_response?
              receive_response(payload.response)
            when payload.has_resolve?
              receive_resolve(payload.resolve)
            end
            yield send_queue.pop
          end
          notice 'filter end normally.'
        rescue StandardError => e
          error e
          fail e # signal completion via an error
        ensure
          warn 'filter end!'
        end
      end

      def receive_start(start)
        event_name = start.name.to_sym
        plugin.add_event_filter(
          event_name,
          tags: [@tag],
          name: 'mrpc_filter_proxy'
        ) do |*args|
          event_id = 1
          send_request(
            name: event_name,
            event_id: event_id,
            param: args.map(&Plugin::RemotePluginCall.method(:mrpc_param))
          )
        end
      end

      def send_request(name:, event_id:, param:)
        await = @awaiting[event_id] = Queue.new
        send_queue.push(
          ::Mrpc::FilteringRequest.new(
            request: ::Mrpc::FilterQuery.new(
              name: name,
              event_id: event_id,
              param: param,
            )
          )
        )
        await.pop.param.map { |x|
          Plugin::RemotePluginCall.mrpc_param_unbox(x, -> (proxy_object, message) {
                                                      nil # TODO
                                                    })
        }
      end

      def receive_response(response)
        @awaiting.fetch(response.event_id).push(response)
        @awaiting.delete(response.event_id)
      end

      def receive_resolve(resolve)
        
      end

      private

      def plugin
        Plugin[:mrpc]
      end
    end
  end
end
