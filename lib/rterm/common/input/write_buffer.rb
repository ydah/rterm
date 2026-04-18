# frozen_string_literal: true

module RTerm
  module Common
    # Small FIFO write buffer used by CoreTerminal before parsing.
    class WriteBuffer
      # @param auto_flush [Boolean]
      # @yield [String] receives flushed chunks
      def initialize(auto_flush: true, &consumer)
        @consumer = consumer
        @auto_flush = auto_flush
        @queue = []
      end

      # @param data [String]
      # @return [void]
      def write(data)
        @queue << data.to_s
        flush if @auto_flush
      end

      # @return [void]
      def flush
        raise ArgumentError, "WriteBuffer requires a consumer block" unless @consumer

        @consumer.call(@queue.shift) until @queue.empty?
      end

      # @return [Boolean]
      def empty?
        @queue.empty?
      end

      # @return [Integer]
      def length
        @queue.length
      end

      # @return [void]
      def clear
        @queue.clear
      end
    end
  end
end
