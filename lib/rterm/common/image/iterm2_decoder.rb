# frozen_string_literal: true

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
        {
          protocol: :iterm2,
          format: :binary,
          bytes: bytes,
          byte_size: bytes.bytesize,
          name: decoded_name,
          attributes: @attributes.dup,
          width: @attributes["width"],
          height: @attributes["height"],
          inline: @attributes["inline"] == "1"
        }.compact
      end

      private

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
