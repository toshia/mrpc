# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    module Proxy
      module Extend
        def _proxy_revive_dict
          @_proxy_revive_dict ||= {}
        end
      end

      def self.unwrap(proxy)
        klass = proxy_classes[proxy.class_id]
        if klass
          klass._proxy_revive_dict[proxy.id.to_i]
        else
          raise ArgumentError, "The class `#{proxy.class_id}' was not found."
        end
      end

      def self.included(klass)
        klass.extend(Extend)
        proxy_classes[klass.to_s] = klass
      end

      def self.proxy_classes
        @proxy_classes ||= {}
      end

      def _proxy_identity
        self.class._proxy_revive_dict[object_id] = self
        Proxy.proxy_classes[self.class.to_s] ||= self.class
        object_id.to_s
      end
    end
  end
end
