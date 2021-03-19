# frozen_string_literal: true

class Plugin
  module RemotePluginCall
    class FilteringRequestSender
      attr_reader :queue

      def initialize
        @queue = Queue.new # Mrpc::FilteringRequest
        @res = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = Set[] } }
      end

      def request(message)
        @queue.push(::Mrpc::FilteringRequest.new(request: message))
      end

      # mRPC nodeにProxyObjectの解決をリクエストする。
      # このメソッドは、mRPC nodeからレスポンスがあるまで処理をブロックする
      # @params [ProxyObject] target クエリ対象オブジェクト
      # @params [String] selection 送信するメッセージ
      # @return [::Mrpc::Param] クエリ結果
      def query(target:, selection:)
        response = Queue.new
        atomic { @res[target.proxy][selection] << response }
        @queue.push(
          ::Mrpc::FilteringRequest.new(
            query: ::Mrpc::ProxyQuery.new(
              subject: target.proxy,
              selection: selection
            )
          )
        )
        response.pop
      ensure
        response&.close
      end

      # クエリの解決レスポンスを得た時に呼ばれる
      # @params [::Mrpc::ProxyValue] 通知する値
      def resolve(proxy_value)
        subject = proxy_value.subject
        selection = proxy_value.selection
        if subject && selection
          SerialThread.new do
            atomic {
              queues = @res[subject][selection]
              notify_to = queues.dup
              queues.clear
              notify_to
            }.each do |queue|
              queue.push(proxy_value)
            rescue ClosedQueueError
              warn "found closed queue for `#{proxy_value.inspect}'"
            end
          end
        end
      end

      def close
        queue.close
      end

      def closed?
        queue.closed?
      end
    end
  end
end
