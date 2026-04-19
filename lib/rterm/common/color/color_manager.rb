# frozen_string_literal: true

require_relative "../buffer/constants"
require_relative "color_palette"

module RTerm
  module Common
    # Tracks mutable terminal colors from OSC color sequences.
    class ColorManager
      include BufferConstants

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

      # Resolves a cell's render colors according to terminal options.
      # This is renderer-facing policy; the cell's packed attributes are unchanged.
      # @param cell [CellData]
      # @param options [Hash]
      # @return [Hash]
      def resolve_cell_colors(cell, options = {})
        fg = resolve_color(cell.fg, default: @foreground)
        bg = resolve_color(cell.bg, default: @background)
        fg = bold_bright_color(cell, fg, options)
        bg = @theme.background if bg == "transparent" && !options[:allow_transparency]
        fg = contrast_color(fg, bg, options.fetch(:minimum_contrast_ratio, 1).to_f)
        { foreground: fg, background: bg }
      end

      private

      def resolve_color(packed, default:)
        case packed & ColorMode::MASK
        when ColorMode::P16
          @palette[packed & Color::PCOLOR_MASK]
        when ColorMode::P256
          @palette[packed & Color::PCOLOR_MASK]
        when ColorMode::RGB
          rgb_to_hex(
            (packed & Color::RED_MASK) >> Color::RED_SHIFT,
            (packed & Color::GREEN_MASK) >> Color::GREEN_SHIFT,
            packed & Color::BLUE_MASK
          )
        else
          default
        end
      end

      def bold_bright_color(cell, color, options)
        return color unless options.fetch(:draw_bold_text_in_bright_colors, true)
        return color unless cell.bold? && cell.fg_color_mode == :p16

        index = cell.fg_color & Color::PCOLOR_MASK
        index < 8 ? @palette[index + 8] : color
      end

      def contrast_color(foreground_color, background_color, minimum_ratio)
        return foreground_color if minimum_ratio <= 1
        return foreground_color unless hex_color?(foreground_color) && hex_color?(background_color)
        return foreground_color if contrast_ratio(foreground_color, background_color) >= minimum_ratio

        black_ratio = contrast_ratio("#000000", background_color)
        white_ratio = contrast_ratio("#ffffff", background_color)
        black_ratio > white_ratio ? "#000000" : "#ffffff"
      end

      def contrast_ratio(a, b)
        dark, light = [relative_luminance(a), relative_luminance(b)].sort
        (light + 0.05) / (dark + 0.05)
      end

      def relative_luminance(color)
        rgb = color.delete_prefix("#").scan(/../).map { |part| part.to_i(16) / 255.0 }
        channels = rgb.map do |value|
          value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
        end
        (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
      end

      def hex_color?(value)
        value.to_s.match?(/\A#[0-9a-f]{6}\z/i)
      end

      def rgb_to_hex(red, green, blue)
        format("#%02x%02x%02x", red, green, blue)
      end
    end
  end
end
