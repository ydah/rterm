# frozen_string_literal: true

module RTerm
  module Common
    # Character translation table used by ISO-2022 charset designations.
    class CharsetTable
      # @param mapping [Hash<String, String>]
      def initialize(mapping = {})
        @mapping = mapping.freeze
      end

      # @param char [String]
      # @return [String]
      def translate(char)
        @mapping.fetch(char, char)
      end
    end
  end
end
