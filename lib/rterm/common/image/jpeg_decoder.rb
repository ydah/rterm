# frozen_string_literal: true

module RTerm
  module Common
    class JpegDecoder
      START = "\xff\xd8".b
      FINISH = 0xd9
      START_OF_SCAN = 0xda
      SOF_MARKERS = [
        0xc0, 0xc1, 0xc2, 0xc3,
        0xc5, 0xc6, 0xc7,
        0xc9, 0xca, 0xcb,
        0xcd, 0xce, 0xcf
      ].freeze

      def self.decode(bytes)
        new(bytes).decode
      end

      def initialize(bytes)
        @bytes = bytes.to_s.b
        @index = 2
      end

      def decode
        return nil unless jpeg?

        scan_segments
      rescue ArgumentError
        nil
      end

      private

      def jpeg?
        @bytes.start_with?(START)
      end

      def scan_segments
        until @index >= @bytes.bytesize
          marker = next_marker
          return nil if marker.nil? || marker == FINISH
          return nil if marker == START_OF_SCAN
          next if standalone_marker?(marker)

          length = read_u16
          payload = read(length - 2)
          return frame_payload(marker, payload) if SOF_MARKERS.include?(marker)
        end
        nil
      end

      def frame_payload(marker, payload)
        precision = payload.getbyte(0)
        height = payload.byteslice(1, 2).unpack1("n")
        width = payload.byteslice(3, 2).unpack1("n")
        components = payload.getbyte(5)
        {
          format: :sampled,
          media_type: :jpeg,
          width: width,
          height: height,
          precision: precision,
          components: components,
          progressive: marker == 0xc2
        }
      end

      def next_marker
        @index += 1 while @index < @bytes.bytesize && @bytes.getbyte(@index) != 0xff
        @index += 1 while @index < @bytes.bytesize && @bytes.getbyte(@index) == 0xff
        marker = @bytes.getbyte(@index)
        @index += 1
        marker
      end

      def standalone_marker?(marker)
        marker == 0x01 || (0xd0..0xd7).include?(marker)
      end

      def read_u16
        data = read(2)
        data.unpack1("n")
      end

      def read(length)
        data = @bytes.byteslice(@index, length)
        raise ArgumentError, "truncated JPEG" unless data && data.bytesize == length

        @index += length
        data
      end
    end
  end
end
