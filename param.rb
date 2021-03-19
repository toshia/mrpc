# frozen_string_literal: true

class Plugin
  module RemotePluginCall
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

    # @param box [Mrpc::Param] unboxする対象
    def self.mrpc_param_unbox(box, unbox_requester)
      if box.has_sval?
        box.sval
      elsif box.has_ival?
        box.ival
      elsif box.has_dval?
        box.dval
      elsif box.has_bval?
        box.bval
      elsif box.has_time?
        Time.at(box.time.seconds, box.time.nanos, :nanosecond, in: 'UTC')
      elsif box.has_proxy?
        Plugin::RemotePluginCall::ProxyObject.new(box.proxy, unbox_requester)
      elsif box.has_error?
        error "unboxing error #{box.error.inspect}"
        nil
      elsif box.has_sequence?
        box.sequence.val.lazy.map { |v| mrpc_param_unbox(v, unbox_requester) }
      end
    end
  end
end
