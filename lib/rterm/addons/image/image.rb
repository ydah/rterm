# frozen_string_literal: true

require_relative "../base"
require_relative "../../common/event_emitter"
require_relative "../../common/image/iterm2_decoder"
require_relative "../../common/image/sixel_decoder"

module RTerm
  module Addon
    class Image < Base
      include Common::EventEmitter

      def initialize(decoder: nil, renderer: nil)
        @decoder = decoder
        @renderer = renderer
        @decoders = default_decoders
        @render_requests = []
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

      def register_decoder(protocol, decoder = nil, &block)
        callable = block || decoder
        raise ArgumentError, "decoder must respond to call" unless callable.respond_to?(:call)

        key = protocol.to_sym
        @decoders[key] = callable
        Common::Disposable.new { @decoders.delete(key) if @decoders[key].equal?(callable) }
      end

      def decode(image)
        ensure_active!

        payload = normalize_image(image)
        decoder = @decoders[payload[:protocol]] || @decoder
        return nil unless decoder.respond_to?(:call)

        result = decoder.call(payload)
        event = {
          image: payload,
          protocol: payload[:protocol],
          result: result
        }
        emit(:decode, event)
        event
      end

      def render(image, target: nil, decode: true)
        ensure_active!

        payload = normalize_image(image)
        decoded = decode ? self.decode(payload) : nil
        request = {
          image: payload,
          protocol: payload[:protocol],
          target: target,
          decoded: decoded&.fetch(:result, nil)
        }.compact

        renderer = @renderer
        request[:result] = renderer.call(request) if renderer.respond_to?(:call)
        @render_requests << deep_dup(request)
        emit(:render_request, request)
        request
      end

      def render_all(protocol: nil, buffer: nil, target: nil)
        images.select { |image| matches_filter?(image, protocol: protocol, buffer: buffer) }
              .map { |image| render(image, target: target) }
      end

      def render_requests
        @render_requests.map { |request| deep_dup(request) }
      end

      def on_image(&block)
        on(:image, &block)
      end

      def on_clear(&block)
        on(:clear, &block)
      end

      def on_decode(&block)
        on(:decode, &block)
      end

      def on_render_request(&block)
        on(:render_request, &block)
      end

      def dispose
        @disposables.each(&:dispose)
        @disposables.clear
        super
      end

      alias onImage on_image
      alias onClear on_clear
      alias onDecode on_decode
      alias onRenderRequest on_render_request
      alias byProtocol by_protocol
      alias registerDecoder register_decoder
      alias renderAll render_all
      alias renderRequests render_requests

      private

      def ensure_active!
        raise RuntimeError, "Image addon is not active" unless @terminal
      end

      def default_decoders
        {
          sixel: ->(image) { Common::SixelDecoder.decode(image) },
          iterm2: ->(image) { Common::Iterm2Decoder.decode(image) }
        }
      end

      def matches_filter?(image, protocol:, buffer:)
        return false if protocol && image[:protocol] != protocol.to_sym

        placement = image[:placement] || {}
        return false if buffer && placement[:buffer] != buffer.to_sym

        true
      end

      def normalize_image(image)
        image.to_h.each_with_object({}) do |(key, value), result|
          normalized_key = key.to_s
                              .tr("-", "_")
                              .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
                              .downcase
                              .to_sym
          result[normalized_key] = deep_dup(value)
        end
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key] = deep_dup(item) }
        when Array
          value.map { |item| deep_dup(item) }
        else
          value
        end
      end
    end
  end
end
