# frozen_string_literal: true

$LOAD_PATH << File.join(__dir__, 'gen')
require 'service_services_pb.rb'
require 'pry'

module Plugin::RemotePluginCall
  class Server < ::Mrpc::PluggaloidService::Service

    # @params q ::Mrpc::ProxyValue
    def query(q, _call)
      method = q.selection
      value = Plugin::RemotePluginCall::Proxy.unwrap(q.subject)
      ::Mrpc::ProxyValue.new(
        subject: q.subject,
        response: Plugin::RemotePluginCall.mrpc_param(value.public_send(method))
      )
    end

    def subscribe(request, _call)
      queue = Queue.new
      Plugin[:remote_plugin_call].add_event(request.name) do |*args|
        queue.push ::Mrpc::Event.new(
          name: request.name,
          param: args.map(&Plugin::RemotePluginCall.method(:mrpc_param))
        )
      end
      Enumerator.new do |y|
        loop do
          y << queue.pop
        end
      end
    end
  end

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
      proxy_classes[klass.to_s] = klass
      klass.extend(Extend)
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

  def self.mrpc_param(arg)
    case arg
    when nil
      ::Mrpc::Param.new
    when String, Symbol
      ::Mrpc::Param.new(sval: arg.to_s)
    when Integer
      ::Mrpc::Param.new(ival: arg.to_i)
    when Float
      ::Mrpc::Param.new(dval: arg.to_f)
    when true, false
      ::Mrpc::Param.new(bval: arg)
    when Time
      time = arg.getutc
      ::Mrpc::Param.new(
        time: { seconds: time.tv_sec, nanos: time.nsec }
      )
    when Plugin::RemotePluginCall::Proxy
      ::Mrpc::Param.new(
        proxy: {
          class_id: arg.class.to_s,
          id: arg._proxy_identity
        }
      )
    when Enumerable
      ::Mrpc::Param.new(
        sequence: {
          val: arg.map(&method(:mrpc_param))
        }
      )
    else
      ::Mrpc::Param.new(error: arg.inspect)
    end
  end
end

class Diva::Model
  include Plugin::RemotePluginCall::Proxy
end

Plugin.create(:remote_plugin_call) do
  Thread.new do
    loop do
      begin
        port = '0.0.0.0:50051'
        s = GRPC::RpcServer.new
        s.add_http2_port(port, :this_port_is_insecure)
        s.handle(Plugin::RemotePluginCall::Server.new())
        warn 'Plugin::RemotePluginCall::Server start'
        s.run
      rescue Exception => e
        warn e
      end
      warn 'Plugin::RemotePluginCall::Server crashed. restart in 1 second'
      sleep 1
    end
  end
end
