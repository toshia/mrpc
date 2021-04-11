# frozen_string_literal: true

__dir__&.yield_self do |dir|
  $LOAD_PATH << File.join(dir, 'gen')
end
require 'service_services_pb'
require_relative 'lib/filtering_requester'
require_relative 'lib/param'
require_relative 'lib/proxy_object'
require_relative 'lib/server_impl'

class Diva::Model
  include Pluggaloid::Mirage
end

Plugin.create(:remote_plugin_call) do
  Thread.new do
    loop do
      begin
        port = '0.0.0.0:50051'
        s = GRPC::RpcServer.new
        s.add_http2_port(port, :this_port_is_insecure)
        s.handle(Plugin::RemotePluginCall::Server.new)
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
