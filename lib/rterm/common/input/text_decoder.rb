# frozen_string_literal: true

module RTerm
  module Common
    # Decodes terminal byte streams into UTF-8 strings.
    class TextDecoder
      # @param encoding [Encoding]
      def initialize(encoding = Encoding::UTF_8)
        @encoding = encoding
      end

      # @param data [String]
      # @return [String]
      def decode(data)
        data.to_s.dup.force_encoding(@encoding).scrub
      end
    end
  end
end
