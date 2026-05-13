# frozen_string_literal: true

require_relative "../base"
require_relative "../../common/event_emitter"

module RTerm
  module Addon
    class Image < Base
      include Common::EventEmitter

      def initialize
        @disposables = []
      end

      def activate(terminal)
        super
        @disposables << terminal.on(:image) { |payload| emit(:image, payload) }
      end

      def images
        ensure_active!

        @terminal.images.dup
      end

      def count
        images.length
      end

      def empty?
        count.zero?
      end

      def protocols
        images.map { |image| image[:protocol] }.compact.uniq
      end

      def by_protocol(protocol)
        key = protocol.to_sym
        images.select { |image| image[:protocol] == key }
      end

      def at(row, col, buffer: nil)
        images.find do |image|
          occupancy = image[:occupancy] || {}
          next false if buffer && occupancy[:buffer] != buffer.to_sym

          Array(occupancy[:cells]).any? { |cell| cell[:row] == row.to_i && cell[:col] == col.to_i }
        end
      end

      def clear(protocol: nil, buffer: nil)
        ensure_active!

        removed = []
        @terminal.images.delete_if do |image|
          next false unless matches_filter?(image, protocol: protocol, buffer: buffer)

          removed << image
          true
        end
        emit(:clear, removed) unless removed.empty?
        removed
      end

      def on_image(&block)
        on(:image, &block)
      end

      def on_clear(&block)
        on(:clear, &block)
      end

      def dispose
        @disposables.each(&:dispose)
        @disposables.clear
        super
      end

      alias onImage on_image
      alias onClear on_clear
      alias byProtocol by_protocol

      private

      def ensure_active!
        raise RuntimeError, "Image addon is not active" unless @terminal
      end

      def matches_filter?(image, protocol:, buffer:)
        return false if protocol && image[:protocol] != protocol.to_sym

        placement = image[:placement] || {}
        return false if buffer && placement[:buffer] != buffer.to_sym

        true
      end
    end
  end
end
