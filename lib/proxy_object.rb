# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    class ProxyObject < BasicObject
      include ::Pluggaloid::Mirage
      attr_reader :proxy

      def initialize(proxy, unbox_requester)
        @proxy = proxy
        @unbox_requester = unbox_requester
        @cache = {}
      end

      def method_missing(message, *rest, **kwrest)
        if @cache.has_key?(message)
          @cache[message]
        else
          @cache[message] = @unbox_requester.call(self, message)
        end
      end

      def ==(other)
        case other
        when Mrpc::Proxy
          other == proxy
        when Plugin::RemotePluginCall::ProxyObject
          other.proxy == proxy
        when ::Pluggaloid::Mirage
          other.pluggaloid_mirage_namespace == proxy.class_id &&
            other.pluggaloid_mirage_id == proxy.id
        end
      end

      def inspect
        "#<Plugin::RemotePluginCall::ProxyObject: #{proxy.inspect}>"
      end
    end
  end
end
