# frozen_string_literal: true

module RTerm
  module Services
    class CharSizeService
      attr_reader :width, :height

      def initialize(width: 0, height: 0)
        @width = width.to_f
        @height = height.to_f
      end

      def measure(width:, height:)
        @width = width.to_f
        @height = height.to_f
        size
      end

      def size
        { width: @width, height: @height }
      end
    end
  end
end
