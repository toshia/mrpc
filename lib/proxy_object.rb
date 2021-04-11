# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    class ProxyObject < BasicObject
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
    end
  end
end
