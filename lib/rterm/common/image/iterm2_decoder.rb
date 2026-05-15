# frozen_string_literal: true

require_relative "png_decoder"

module RTerm
  module Common
    class Iterm2Decoder
      def self.decode(image)
        new(image).decode
      end

      def initialize(image)
        @image = image.to_h
        @attributes = @image[:attributes] || {}
      end

      def decode
        bytes = decode_payload(@image[:data].to_s)
        decoded = decode_binary(bytes)
        payload = {
          protocol: :iterm2,
          bytes: bytes,
          byte_size: bytes.bytesize,
          name: decoded_name,
          attributes: @attributes.dup,
          width: @attributes["width"],
          height: @attributes["height"],
          inline: @attributes["inline"] == "1"
        }
        payload.merge(decoded).compact
      end

      private

      def decode_binary(bytes)
        png = PngDecoder.decode(bytes)
        return png if png

        { format: :binary }
      end

      def decode_payload(data)
        data.unpack1("m0")
      rescue ArgumentError
        data.unpack1("m")
      end

      def decoded_name
        raw = @attributes["name"]
        return nil if raw.to_s.empty?

        decoded = raw.unpack1("m0")
        decoded.valid_encoding? ? decoded : raw
      rescue ArgumentError
        raw
      end
    end
  end
end
