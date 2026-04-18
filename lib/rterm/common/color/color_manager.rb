# frozen_string_literal: true

require_relative "color_palette"

module RTerm
  module Common
    # Tracks mutable terminal colors from OSC color sequences.
    class ColorManager
      attr_reader :theme, :palette
      attr_accessor :foreground, :background, :cursor

      # @param theme [RTerm::Theme]
      def initialize(theme = RTerm::Theme.new)
        @theme = theme
        @palette = ColorPalette.new(theme)
        reset_defaults
      end

      # @param index [Integer]
      # @param color [String]
      # @return [void]
      def set_ansi_color(index, color)
        @palette[index] = color
      end

      # @param index [Integer, nil]
      # @return [void]
      def reset_ansi_color(index = nil)
        @palette.reset(index)
      end

      # @return [void]
      def reset_defaults
        @foreground = @theme.foreground
        @background = @theme.background
        @cursor = @theme.cursor
      end
    end
  end
end
