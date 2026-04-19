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
      #   :exclude_title [Boolean] exclude title/icon name state
      #   :exclude_images [Boolean] exclude image protocol payloads
      # @return [String] serialized terminal state
      def serialize(options = {})
        buffer_set = @terminal.internal.buffer_set
        result = +""
        result << serialize_title unless options[:exclude_title]
        result << serialize_modes unless options[:exclude_modes]
        result << serialize_dynamic_colors unless options[:exclude_colors]
        result << serialize_cursor_style unless options[:exclude_cursor_style]

        if options[:include_alt_buffer] && !options[:exclude_alt_buffer]
          result << serialize_buffer(buffer_set.normal, options.fetch(:scrollback, 0))
          result << serialize_images(buffer_set.normal, options.fetch(:scrollback, 0)) unless options[:exclude_images]
          result << "\e[?1049h"
          result << serialize_buffer(buffer_set.alt, 0)
          result << serialize_images(buffer_set.alt, 0) unless options[:exclude_images]
          result << "\e[?1049l" unless buffer_set.active.equal?(buffer_set.alt)
          return result
        end

        buffer = options[:exclude_alt_buffer] ? buffer_set.normal : buffer_set.active
        result << serialize_buffer(buffer, options.fetch(:scrollback, 0))
        result << serialize_images(buffer, options.fetch(:scrollback, 0)) unless options[:exclude_images]
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

      # Exports a structured, JSON-friendly terminal snapshot.
      # @param options [Hash]
      # @option options [Integer] :scrollback number of normal-buffer scrollback lines to include
      # @option options [Boolean] :exclude_alt_buffer omit alternate buffer state
      # @return [Hash]
      def snapshot(options = {})
        buffer_set = @terminal.internal.buffer_set
        buffers = {
          "normal" => snapshot_buffer(buffer_set.normal, options.fetch(:scrollback, 0))
        }
        buffers["alt"] = snapshot_buffer(buffer_set.alt, 0) unless options[:exclude_alt_buffer]

        {
          "version" => 1,
          "cols" => @terminal.cols,
          "rows" => @terminal.rows,
          "active_buffer" => buffer_set.active.equal?(buffer_set.alt) ? "alt" : "normal",
          "buffers" => buffers,
          "state" => snapshot_state,
          "images" => deep_dup(@terminal.images)
        }
      end

      # Restores a snapshot produced by #snapshot into this addon's terminal.
      # @param data [Hash]
      # @return [RTerm::Terminal]
      def restore(data)
        data = stringify_keys(data)
        @terminal.resize(data.fetch("cols"), data.fetch("rows"))
        buffer_set = @terminal.internal.buffer_set

        restore_buffer(buffer_set.normal, data.fetch("buffers").fetch("normal"))
        restore_buffer(buffer_set.alt, data.fetch("buffers").fetch("alt")) if data.fetch("buffers").key?("alt")
        data["active_buffer"] == "alt" ? buffer_set.activate_alt_buffer : buffer_set.activate_normal_buffer
        restore_state(data["state"] || {})
        @terminal.images.replace(symbolize_image_keys(data["images"] || []))
        @terminal
      end

      alias deserialize restore

      private

      def snapshot_buffer(buffer, scrollback)
        indexes = line_indexes(buffer, scrollback)
        {
          "cols" => buffer.cols,
          "rows" => buffer.rows,
          "x" => buffer.x,
          "y" => buffer.y,
          "y_base" => buffer.y_base,
          "y_disp" => buffer.y_disp,
          "scroll_top" => buffer.scroll_top,
          "scroll_bottom" => buffer.scroll_bottom,
          "saved_cursor" => snapshot_saved_cursor(buffer),
          "lines" => indexes.map { |index| snapshot_line(buffer.lines[index]) }
        }
      end

      def snapshot_line(line)
        line ||= Common::BufferLine.new(@terminal.cols)
        {
          "wrapped" => line.is_wrapped,
          "cells" => line.length.times.map { |index| snapshot_cell(line.get_cell(index)) }
        }
      end

      def snapshot_cell(cell)
        {
          "char" => cell.char,
          "width" => cell.width,
          "fg" => cell.fg,
          "bg" => cell.bg,
          "link" => deep_dup(cell.link)
        }
      end

      def snapshot_state
        handler = @terminal.internal.input_handler
        color_manager = handler.color_manager
        {
          "title" => handler.title,
          "icon_name" => handler.icon_name,
          "modes" => deep_dup(@terminal.modes),
          "cursor_style" => handler.cursor_style.to_s,
          "cursor_blink" => handler.cursor_blink,
          "parser" => snapshot_parser_state,
          "charset" => snapshot_charset_state(handler),
          "current_link" => deep_dup(handler.instance_variable_get(:@current_link)),
          "selection" => deep_dup(@terminal.instance_variable_get(:@selection)),
          "search" => snapshot_search_state,
          "dynamic_colors" => {
            "foreground" => color_manager.foreground,
            "background" => color_manager.background,
            "cursor" => color_manager.cursor,
            "palette" => color_manager.palette.to_a
          }
        }
      end

      def restore_buffer(buffer, data)
        data = stringify_keys(data)
        buffer.lines.clear
        data.fetch("lines").each do |line_data|
          buffer.lines.push(restore_line(line_data, buffer.cols))
        end
        buffer.lines.push(Common::BufferLine.new(buffer.cols)) while buffer.lines.length < buffer.rows

        buffer.x = [[data["x"].to_i, 0].max, buffer.cols - 1].min
        buffer.y = [[data["y"].to_i, 0].max, buffer.rows - 1].min
        buffer.y_base = [buffer.lines.length - buffer.rows, 0].max
        buffer.y_disp = [[data["y_disp"].to_i, 0].max, buffer.y_base].min
        buffer.scroll_top = [[data["scroll_top"].to_i, 0].max, buffer.rows - 1].min
        buffer.scroll_bottom = [[data["scroll_bottom"].to_i, buffer.scroll_top].max, buffer.rows - 1].min
        restore_saved_cursor(buffer, data["saved_cursor"] || {})
      end

      def restore_line(data, cols)
        data = stringify_keys(data)
        line = Common::BufferLine.new(cols)
        Array(data["cells"]).first(cols).each_with_index do |cell_data, index|
          line.set_cell(index, restore_cell(cell_data))
        end
        line.is_wrapped = data["wrapped"] == true
        line
      end

      def restore_cell(data)
        data = stringify_keys(data)
        cell = Common::CellData.new
        cell.width = data.fetch("width", 1).to_i
        cell.char = data["char"].to_s
        cell.fg = data.fetch("fg", 0).to_i
        cell.bg = data.fetch("bg", 0).to_i
        cell.link = symbolize_hash(data["link"]) if data["link"]
        cell
      end

      def restore_state(data)
        data = stringify_keys(data)
        handler = @terminal.internal.input_handler
        handler.instance_variable_set(:@title, data["title"].to_s)
        handler.instance_variable_set(:@icon_name, data["icon_name"].to_s)
        restore_modes(handler, stringify_keys(data["modes"] || {}))
        restore_cursor_state(handler, data)
        restore_parser_state(data["parser"] || {})
        restore_charset_state(handler, data["charset"] || {})
        handler.instance_variable_set(:@current_link, symbolize_hash(data["current_link"]))
        @terminal.instance_variable_set(:@selection, symbolize_hash(data["selection"]))
        restore_search_state(data["search"])
        restore_dynamic_colors(handler.color_manager, stringify_keys(data["dynamic_colors"] || {}))
      end

      def snapshot_saved_cursor(buffer)
        {
          "x" => buffer.saved_x,
          "y" => buffer.saved_y,
          "attr" => buffer.saved_cur_attr ? snapshot_cell(buffer.saved_cur_attr) : nil
        }
      end

      def restore_saved_cursor(buffer, data)
        data = stringify_keys(data)
        buffer.saved_x = [[data["x"].to_i, 0].max, buffer.cols - 1].min
        buffer.saved_y = [[data["y"].to_i, 0].max, buffer.rows - 1].min
        buffer.saved_cur_attr = data["attr"] ? restore_cell(data["attr"]) : nil
      end

      def snapshot_parser_state
        parser = @terminal.internal.parser
        {
          "current_state" => parser.current_state,
          "collect" => parser.instance_variable_get(:@collect),
          "osc_data" => parser.instance_variable_get(:@osc_data).to_s,
          "osc_id" => parser.instance_variable_get(:@osc_id),
          "dcs_data" => parser.instance_variable_get(:@dcs_data).to_s,
          "apc_data" => parser.instance_variable_get(:@apc_data).to_s,
          "sos_pm_data" => parser.instance_variable_get(:@sos_pm_data).to_s,
          "sos_pm_kind" => parser.instance_variable_get(:@sos_pm_kind)&.to_s
        }
      end

      def restore_parser_state(data)
        data = stringify_keys(data)
        parser = @terminal.internal.parser
        parser.instance_variable_set(:@current_state, data["current_state"].to_i)
        parser.instance_variable_set(:@collect, data["collect"].to_i)
        parser.instance_variable_set(:@osc_data, data["osc_data"].to_s)
        parser.instance_variable_set(:@osc_id, data.fetch("osc_id", -1).to_i)
        parser.instance_variable_set(:@dcs_data, data["dcs_data"].to_s)
        parser.instance_variable_set(:@apc_data, data["apc_data"].to_s)
        parser.instance_variable_set(:@sos_pm_data, data["sos_pm_data"].to_s)
        parser.instance_variable_set(:@sos_pm_kind, data["sos_pm_kind"]&.to_sym)
      end

      def snapshot_charset_state(handler)
        charsets = handler.instance_variable_get(:@charsets)
        {
          "active" => handler.instance_variable_get(:@charset_g),
          "slots" => charsets.map { |charset| charset_name(charset) }
        }
      end

      def restore_charset_state(handler, data)
        data = stringify_keys(data)
        slots = Array(data["slots"])
        handler.instance_variable_set(:@charset_g, data["active"].to_i)
        handler.instance_variable_set(
          :@charsets,
          [charset_from_name(slots[0] || :ascii), charset_from_name(slots[1] || :ascii)]
        )
      end

      def charset_from_name(name)
        Common::Charsets::TABLES[name] || Common::Charsets::TABLES[name.to_s] ||
          Common::Charsets::TABLES[name.to_s.to_sym] || Common::Charsets::ASCII
      end

      def charset_name(charset)
        Common::Charsets::TABLES.each do |name, table|
          return name.to_s if table.equal?(charset)
        end
        "ascii"
      end

      def restore_modes(handler, modes)
        {
          "@application_cursor_keys_mode" => "application_cursor_keys_mode",
          "@application_keypad_mode" => "application_keypad_mode",
          "@bracketed_paste_mode" => "bracketed_paste_mode",
          "@cursor_hidden" => "cursor_hidden",
          "@focus_event_mode" => "focus_event_mode",
          "@insert_mode" => "insert_mode",
          "@origin_mode" => "origin_mode",
          "@reverse_wraparound" => "reverse_wraparound_mode",
          "@sgr_mouse_mode" => "sgr_mouse_mode",
          "@urxvt_mouse_mode" => "urxvt_mouse_mode",
          "@utf8_mouse_mode" => "utf8_mouse_mode",
          "@autowrap" => "wraparound_mode"
        }.each do |ivar, key|
          handler.instance_variable_set(ivar, modes[key] == true)
        end
        handler.instance_variable_set(:@mouse_tracking_mode, modes["mouse_tracking_mode"]&.to_sym)
      end

      def restore_cursor_state(handler, data)
        handler.instance_variable_set(:@cursor_style, data["cursor_style"].to_s.to_sym)
        handler.instance_variable_set(:@cursor_blink, data["cursor_blink"] == true)
      end

      def restore_dynamic_colors(color_manager, data)
        color_manager.foreground = data["foreground"] if data["foreground"]
        color_manager.background = data["background"] if data["background"]
        color_manager.cursor = data["cursor"] if data["cursor"]
        Array(data["palette"]).each_with_index do |color, index|
          color_manager.set_ansi_color(index, color) if color
        end
      end

      def snapshot_search_state
        addon = search_addon
        addon ? deep_dup(addon.state) : nil
      end

      def restore_search_state(data)
        return unless data

        addon = search_addon
        addon&.restore_state(data, emit: false)
      end

      def search_addon
        loaded_addons.find do |addon|
          addon.respond_to?(:state) && addon.respond_to?(:restore_state) &&
            addon.class.name == "RTerm::Addon::Search"
        end
      end

      def loaded_addons
        @terminal.instance_variable_get(:@addons) || []
      end

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
        result << "\e[?1h" if modes[:application_cursor_keys_mode]
        result << "\e=" if modes[:application_keypad_mode]
        result << "\e[?7l" unless modes[:wraparound_mode]
        result << "\e[?12h" if modes[:cursor_blink]
        result << "\e[4h" if modes[:insert_mode]
        result << "\e[?6h" if modes[:origin_mode]
        result << "\e[?45h" if modes[:reverse_wraparound_mode]
        result << "\e[?25l" if modes[:cursor_hidden]
        result << serialize_mouse_modes(modes)
        result << "\e[?1004h" if modes[:focus_event_mode]
        result << "\e[?2004h" if modes[:bracketed_paste_mode]
        result
      end

      def serialize_mouse_modes(modes)
        result = +""
        case modes[:mouse_tracking_mode]
        when :x10 then result << "\e[?1000h"
        when :button then result << "\e[?1002h"
        when :any then result << "\e[?1003h"
        end
        result << "\e[?1005h" if modes[:utf8_mouse_mode]
        result << "\e[?1006h" if modes[:sgr_mouse_mode]
        result << "\e[?1015h" if modes[:urxvt_mouse_mode]
        result
      end

      def serialize_title
        handler = @terminal.internal.input_handler
        result = +""
        result << "\e]1;#{handler.icon_name}\a" unless handler.icon_name.to_s.empty?
        result << "\e]2;#{handler.title}\a" unless handler.title.to_s.empty?
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

      def serialize_images(buffer, scrollback)
        indexes = line_indexes(buffer, scrollback)
        index_offset = indexes.first || 0
        buffer_name = buffer.equal?(@terminal.internal.buffer_set.alt) ? :alt : :normal

        @terminal.images.filter_map do |image|
          placement = image[:placement] || {}
          next unless placement[:buffer] == buffer_name
          next unless indexes.include?(placement[:row])

          row = placement[:row] - index_offset
          col = placement[:col].to_i
          raw_sequence = image[:raw_sequence]
          next unless raw_sequence

          "\e[#{row + 1};#{col + 1}H#{raw_sequence}"
        end.join
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

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), copy| copy[key] = deep_dup(entry) }
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
      end

      def stringify_keys(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, entry), result|
          result[key.to_s] = entry.is_a?(Hash) ? stringify_keys(entry) : entry
        end
      end

      def symbolize_hash(value)
        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, entry), result|
          result[key.to_sym] = entry.is_a?(Hash) ? symbolize_hash(entry) : entry
        end
      end

      def symbolize_image_keys(images)
        images.map { |image| symbolize_hash(image) }
      end
    end
  end
end
