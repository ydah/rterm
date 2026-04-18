# frozen_string_literal: true

require_relative "../../theme"

module RTerm
  module Common
    # xterm-compatible 256 color palette.
    class ColorPalette
      ANSI_KEYS = %i[
        black red green yellow blue magenta cyan white
        bright_black bright_red bright_green bright_yellow
        bright_blue bright_magenta bright_cyan bright_white
      ].freeze

      # @param theme [RTerm::Theme]
      def initialize(theme = RTerm::Theme.new)
        @theme = theme
        @colors = build_palette
      end

      # @param index [Integer]
      # @return [String, nil]
      def [](index)
        @colors[index]
      end

      # @param index [Integer]
      # @param color [String]
      def []=(index, color)
        validate_index(index)
        @colors[index] = color
      end

      # @return [Array<String>]
      def to_a
        @colors.dup
      end

      # @param index [Integer]
      # @return [void]
      def reset(index = nil)
        fresh = build_palette
        if index
          validate_index(index)
          @colors[index] = fresh[index]
        else
          @colors = fresh
        end
      end

      private

      def build_palette
        colors = ANSI_KEYS.map { |key| @theme.public_send(key) }
        colors.concat(color_cube)
        colors.concat(grayscale_ramp)
      end

      def color_cube
        levels = [0, 95, 135, 175, 215, 255]
        levels.product(levels, levels).map { |red, green, blue| hex(red, green, blue) }
      end

      def grayscale_ramp
        24.times.map do |index|
          value = 8 + (index * 10)
          hex(value, value, value)
        end
      end

      def hex(red, green, blue)
        format("#%02x%02x%02x", red, green, blue)
      end

      def validate_index(index)
        return if index.between?(0, 255)

        raise ArgumentError, "Palette index must be between 0 and 255"
      end
    end
  end
end
