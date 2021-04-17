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
      when Pluggaloid::Mirage
        ::Mrpc::Param.new(
          proxy: {
            class_id: arg.class.to_s,
            id: arg.pluggaloid_mirage_id
          }
        )
      when Enumerable
        ::Mrpc::Param.new(
          sequence: {
            val: arg.map(&method(:mrpc_param)).to_a
          }
        )
      else
        ::Mrpc::Param.new(error: arg.inspect)
      end
    end

    # @param box [Mrpc::Param] unboxする対象
    def self.mrpc_param_unbox(box, unbox_requester)
      case box.val
      when :sval
        box.sval
      when :ival
        box.ival
      when :dval
        box.dval
      when :bval
        box.bval
      when :time
        Time.at(box.time.seconds, box.time.nanos, :nanosecond, in: 'UTC')
      when :proxy
        Plugin::RemotePluginCall::ProxyObject.new(box.proxy, unbox_requester)
      when :error
        error "unboxing error #{box.error.inspect}"
        nil
      when :sequence
        box.sequence.val.lazy.map { |v| mrpc_param_unbox(v, unbox_requester) }
      end
    end
  end
end
