# frozen_string_literal: true

require 'cgi'
require_relative "../base"
require_relative "../../common/color/color_palette"

module RTerm
  module Addon
    class Serialize < Base
      ANSI_COLORS = {
        0 => 30, 1 => 31, 2 => 32, 3 => 33,
        4 => 34, 5 => 35, 6 => 36, 7 => 37,
        8 => 90, 9 => 91, 10 => 92, 11 => 93,
        12 => 94, 13 => 95, 14 => 96, 15 => 97
      }.freeze

      ANSI_BG_COLORS = {
        0 => 40, 1 => 41, 2 => 42, 3 => 43,
        4 => 44, 5 => 45, 6 => 46, 7 => 47,
        8 => 100, 9 => 101, 10 => 102, 11 => 103,
        12 => 104, 13 => 105, 14 => 106, 15 => 107
      }.freeze

      CSS_COLORS = %w[
        black red green yellow blue magenta cyan white
        #808080 #ff0000 #00ff00 #ffff00 #0000ff #ff00ff #00ffff #ffffff
      ].freeze

      # Serialize terminal state to ANSI escape sequence string
      # @param options [Hash]
      #   :scrollback [Integer] number of scrollback lines to include (default: 0)
      #   :exclude_modes [Boolean] exclude mode information
      #   :exclude_alt_buffer [Boolean] exclude alt buffer
      #   :include_alt_buffer [Boolean] serialize normal and alternate buffers
      #   :exclude_colors [Boolean] exclude OSC dynamic color state
      #   :exclude_cursor_style [Boolean] exclude DECSCUSR cursor style state
      # @return [String] serialized terminal state
      def serialize(options = {})
        buffer_set = @terminal.internal.buffer_set
        result = +""
        result << serialize_modes unless options[:exclude_modes]
        result << serialize_dynamic_colors unless options[:exclude_colors]
        result << serialize_cursor_style unless options[:exclude_cursor_style]

        if options[:include_alt_buffer] && !options[:exclude_alt_buffer]
          result << serialize_buffer(buffer_set.normal, options.fetch(:scrollback, 0))
          result << "\e[?1049h"
          result << serialize_buffer(buffer_set.alt, 0)
          result << "\e[?1049l" unless buffer_set.active.equal?(buffer_set.alt)
          return result
        end

        buffer = options[:exclude_alt_buffer] ? buffer_set.normal : buffer_set.active
        result << serialize_buffer(buffer, options.fetch(:scrollback, 0))
        result
      end

      def serialize_buffer(buffer, scrollback)
        result = +""
        prev_fg = 0
        prev_bg = 0
        prev_link = nil
        indexes = line_indexes(buffer, scrollback)

        indexes.each_with_index do |line_index, index|
          line = buffer.lines[line_index]
          next unless line

          prev_fg, prev_bg, prev_link = serialize_line(line, result, prev_fg, prev_bg, prev_link)
          result << "\r\n" if index < indexes.length - 1
        end

        result << close_link_sequence if prev_link
        result << "\e[0m" if prev_fg != 0 || prev_bg != 0
        result << cursor_position(buffer)

        result
      end

      # Serialize as HTML
      # @param options [Hash]
      # @return [String] HTML representation
      def serialize_as_html(options = {})
        buffer_set = @terminal.internal.buffer_set
        buffer = options[:exclude_alt_buffer] ? buffer_set.normal : buffer_set.active
        result = +"<pre>"

        indexes = line_indexes(buffer, options.fetch(:scrollback, 0))
        indexes.each_with_index do |line_index, index|
          line = buffer.lines[line_index]
          next unless line

          spans = group_cells_by_attrs(line)
          spans.each do |span|
            style = build_css_style(span[:fg], span[:bg])
            if style.empty?
              result << escape_html(span[:text])
            else
              result << "<span style=\"#{style}\">#{escape_html(span[:text])}</span>"
            end
          end

          result << "\n" if index < indexes.length - 1
        end

        result << "</pre>"
        result
      end

      private

      def serialize_line(line, result, prev_fg, prev_bg, prev_link)
        line.length.times do |x|
          cell = line.get_cell(x)
          next unless cell
          next if cell.width == 0

          link = normalized_link(cell.link)
          unless link == prev_link
            result << close_link_sequence if prev_link
            result << open_link_sequence(link) if link
            prev_link = link
          end

          if cell.fg != prev_fg || cell.bg != prev_bg
            sgr = build_sgr(cell)
            result << sgr unless sgr.empty?
            prev_fg = cell.fg
            prev_bg = cell.bg
          end

          result << (cell.has_content? ? cell.char : " ")
        end

        [prev_fg, prev_bg, prev_link]
      end

      def line_indexes(buffer, scrollback)
        scrollback = [scrollback.to_i, 0].max
        start = [buffer.y_base - scrollback, 0].max
        finish = [buffer.y_base + buffer.rows - 1, buffer.lines.length - 1].min
        (start..finish).to_a
      end

      def serialize_modes
        modes = @terminal.modes
        result = +""
        result << "\e[?7l" unless modes[:wraparound_mode]
        result << "\e[4h" if modes[:insert_mode]
        result << "\e[?6h" if modes[:origin_mode]
        result << "\e[?25l" if modes[:cursor_hidden]
        result << "\e[?2004h" if modes[:bracketed_paste_mode]
        result
      end

      def serialize_dynamic_colors
        color_manager = @terminal.internal.input_handler.color_manager
        result = +""
        result << "\e]10;#{color_manager.foreground}\a" if color_manager.foreground
        result << "\e]11;#{color_manager.background}\a" if color_manager.background
        result << "\e]12;#{color_manager.cursor}\a" if color_manager.cursor

        default_palette = Common::ColorPalette.new(color_manager.theme)
        color_manager.palette.to_a.each_with_index do |color, index|
          result << "\e]4;#{index};#{color}\a" if color != default_palette[index]
        end
        result
      end

      def serialize_cursor_style
        "\e[#{cursor_style_param} q"
      end

      def cursor_style_param
        case @terminal.internal.input_handler.cursor_style
        when :blinking_block then 1
        when :block then 2
        when :blinking_underline then 3
        when :underline then 4
        when :blinking_bar then 5
        when :bar then 6
        else 2
        end
      end

      def cursor_position(buffer)
        "\e[#{buffer.y + 1};#{buffer.x + 1}H"
      end

      def normalized_link(link)
        return nil unless link

        uri = link[:uri] || link["uri"]
        return nil if uri.to_s.empty?

        {
          params: (link[:params] || link["params"] || "").to_s,
          uri: uri.to_s
        }
      end

      def open_link_sequence(link)
        "\e]8;#{link[:params]};#{link[:uri]}\a"
      end

      def close_link_sequence
        "\e]8;;\a"
      end

      def build_sgr(cell)
        params = []

        # Reset first
        params << 0

        params << 1 if cell.bold?
        params << 2 if cell.dim?
        params << 3 if cell.italic?
        params << 4 if cell.underline?
        params << 5 if cell.blink?
        params << 7 if cell.inverse?
        params << 8 if cell.invisible?
        params << 9 if cell.strikethrough?

        # Foreground color
        case cell.fg_color_mode
        when :p16
          code = ANSI_COLORS[cell.fg_color & 0xFF]
          params << code if code
        when :p256
          params << 38 << 5 << (cell.fg_color & 0xFF)
        when :rgb
          params << 38 << 2 << cell.fg_red << cell.fg_green << cell.fg_blue
        end

        # Background color
        case cell.bg_color_mode
        when :p16
          code = ANSI_BG_COLORS[cell.bg_color & 0xFF]
          params << code if code
        when :p256
          params << 48 << 5 << (cell.bg_color & 0xFF)
        when :rgb
          params << 48 << 2 << cell.bg_red << cell.bg_green << cell.bg_blue
        end

        "\e[#{params.join(";")}m"
      end

      def group_cells_by_attrs(line)
        spans = []
        current_text = +""
        current_fg = nil
        current_bg = nil

        line.length.times do |x|
          cell = line.get_cell(x)
          next unless cell
          next if cell.width == 0

          if current_fg.nil?
            current_fg = cell.fg
            current_bg = cell.bg
          end

          if cell.fg != current_fg || cell.bg != current_bg
            spans << { text: current_text, fg: current_fg, bg: current_bg } unless current_text.empty?
            current_text = +""
            current_fg = cell.fg
            current_bg = cell.bg
          end

          current_text << (cell.has_content? ? cell.char : " ")
        end

        spans << { text: current_text, fg: current_fg || 0, bg: current_bg || 0 } unless current_text.empty?
        spans
      end

      def build_css_style(fg, bg)
        styles = []

        styles << "font-weight:bold" if (fg & Common::BufferConstants::FgFlags::BOLD) != 0
        styles << "font-style:italic" if (bg & Common::BufferConstants::BgFlags::ITALIC) != 0
        styles << "text-decoration:underline" if (fg & Common::BufferConstants::FgFlags::UNDERLINE) != 0
        styles << "text-decoration:line-through" if (fg & Common::BufferConstants::FgFlags::STRIKETHROUGH) != 0

        css_color_style(fg, styles, "color")
        css_color_style(bg, styles, "background-color")

        styles.join(";")
      end

      def css_color_style(packed, styles, property)
        mode = packed & Common::BufferConstants::ColorMode::MASK
        case mode
        when Common::BufferConstants::ColorMode::P16
          idx = packed & Common::BufferConstants::Color::PCOLOR_MASK
          styles << "#{property}:#{CSS_COLORS[idx]}" if idx < CSS_COLORS.length
        when Common::BufferConstants::ColorMode::P256
          idx = packed & Common::BufferConstants::Color::PCOLOR_MASK
          styles << "#{property}:#{idx < 16 ? CSS_COLORS[idx] : p256_to_hex(idx)}"
        when Common::BufferConstants::ColorMode::RGB
          r = (packed & Common::BufferConstants::Color::RED_MASK) >> Common::BufferConstants::Color::RED_SHIFT
          g = (packed & Common::BufferConstants::Color::GREEN_MASK) >> Common::BufferConstants::Color::GREEN_SHIFT
          b = packed & Common::BufferConstants::Color::BLUE_MASK
          styles << "#{property}:##{format("%02x%02x%02x", r, g, b)}"
        end
      end

      def p256_to_hex(idx)
        if idx < 16
          CSS_COLORS[idx]
        elsif idx < 232
          idx -= 16
          r = (idx / 36) * 51
          g = ((idx % 36) / 6) * 51
          b = (idx % 6) * 51
          format("#%02x%02x%02x", r, g, b)
        else
          v = (idx - 232) * 10 + 8
          format("#%02x%02x%02x", v, v, v)
        end
      end

      def escape_html(text)
        CGI.escapeHTML(text)
      end
    end
  end
end
