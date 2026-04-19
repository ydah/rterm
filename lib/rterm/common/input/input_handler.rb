# frozen_string_literal: true

require_relative "../event_emitter"
require_relative "../buffer/constants"
require_relative "../buffer/cell_data"
require_relative "../charset/charsets"
require_relative "../color/color_manager"
require_relative "../image/sixel_parser"

module RTerm
  module Common
    class InputHandler
      include EventEmitter
      include BufferConstants

      attr_reader :autowrap, :cursor_hidden, :bracketed_paste_mode, :insert_mode,
                  :origin_mode, :application_cursor_keys_mode, :application_keypad_mode,
                  :color_manager, :cursor_style, :cursor_blink, :reverse_wraparound,
                  :title, :icon_name, :images

      def initialize(buffer_set, parser, unicode_handler = nil, options = {})
        if unicode_handler.is_a?(Hash)
          options = unicode_handler
          unicode_handler = nil
        end

        @buffer_set = buffer_set
        @parser = parser
        @unicode_handler = unicode_handler || UnicodeHandler.new
        @cur_attr = CellData.new
        @autowrap = true
        @cursor_hidden = false
        @default_cursor_blink = options[:cursor_blink] == true
        @cursor_blink = @default_cursor_blink
        @bracketed_paste_mode = false
        @insert_mode = false
        @origin_mode = false
        @application_cursor_keys_mode = false
        @application_keypad_mode = false
        @reverse_wraparound = false
        @focus_event_mode = false
        @mouse_tracking_mode = nil
        @sgr_mouse_mode = false
        @utf8_mouse_mode = false
        @urxvt_mouse_mode = false
        @left_right_margin_mode = false
        @left_margin = 0
        @right_margin = nil
        @color_manager = ColorManager.new(options[:theme] || RTerm::Theme.new)
        @default_cursor_style = options[:cursor_style] || :block
        @cursor_style = @default_cursor_style
        @clipboard = {}
        @clipboard_enabled = options.fetch(:clipboard_enabled, true)
        @clipboard_max_bytes = options.fetch(:clipboard_max_bytes, 1_048_576).to_i
        @clipboard_read_handler = options[:clipboard_read_handler]
        @clipboard_write_handler = options[:clipboard_write_handler]
        @images = []
        @title = ""
        @icon_name = ""
        @current_link = nil
        @charset_g = 0
        @charsets = [Charsets.fetch(:ascii), Charsets.fetch(:ascii)]
        @last_printed_char = nil
        @erase_cell = CellData.new
        @print_cell = CellData.new

        register_handlers
      end

      def modes
        {
          application_cursor_keys_mode: @application_cursor_keys_mode,
          application_keypad_mode: @application_keypad_mode,
          bracketed_paste_mode: @bracketed_paste_mode,
          cursor_blink: @cursor_blink,
          cursor_hidden: @cursor_hidden,
          focus_event_mode: @focus_event_mode,
          insert_mode: @insert_mode,
          left_margin: left_margin,
          left_right_margin_mode: @left_right_margin_mode,
          mouse_tracking_mode: @mouse_tracking_mode,
          origin_mode: @origin_mode,
          right_margin: right_margin,
          reverse_wraparound_mode: @reverse_wraparound,
          sgr_mouse_mode: @sgr_mouse_mode,
          urxvt_mouse_mode: @urxvt_mouse_mode,
          utf8_mouse_mode: @utf8_mouse_mode,
          wraparound_mode: @autowrap
        }
      end

      # Encodes and emits a terminal mouse report for the active mouse mode.
      # @param button [Symbol, Integer]
      # @param col [Integer] zero-based column
      # @param row [Integer] zero-based row
      # @param event [Symbol] :press, :release, :motion
      # @param modifiers [Array<Symbol>] :shift, :meta, :ctrl
      # @return [String, nil]
      def mouse_report(button:, col:, row:, event: :press, modifiers: [])
        return nil unless @mouse_tracking_mode

        code = mouse_button_code(button, event, modifiers)
        report = if @sgr_mouse_mode
                   sgr_mouse_report(code, col, row, event)
                 elsif @urxvt_mouse_mode
                   urxvt_mouse_report(code, col, row)
                 else
                   x10_mouse_report(code, col, row)
                 end
        emit(:data, report)
        report
      end

      # Encodes and emits a focus event report if DEC focus reporting is enabled.
      # @param focused [Boolean]
      # @return [String, nil]
      def focus_report(focused)
        return nil unless @focus_event_mode

        report = focused ? "\e[I" : "\e[O"
        emit(:data, report)
        report
      end

      private

      def buffer
        @buffer_set.active
      end

      def left_margin
        @left_right_margin_mode ? @left_margin : 0
      end

      def right_margin
        margin = @left_right_margin_mode ? (@right_margin || buffer.cols - 1) : buffer.cols - 1
        [margin, buffer.cols - 1].min
      end

      def register_handlers
        register_c0_handlers
        register_print_handler
        register_csi_handlers
        register_esc_handlers
        register_osc_handlers
        register_dcs_handlers
      end

      # ── C0 handlers ──

      def register_c0_handlers
        @parser.set_execute_handler(0x07) { emit(:bell) }
        @parser.set_execute_handler(0x08) { cursor_backward(1) }
        @parser.set_execute_handler(0x09) { tab }
        @parser.set_execute_handler(0x0A) { line_feed }
        @parser.set_execute_handler(0x0B) { line_feed }
        @parser.set_execute_handler(0x0C) { line_feed }
        @parser.set_execute_handler(0x0D) { carriage_return }
        @parser.set_execute_handler(0x0E) { @charset_g = 1 }
        @parser.set_execute_handler(0x0F) { @charset_g = 0 }
      end

      # ── Print handler ──

      def register_print_handler
        @parser.set_print_handler do |data|
          print_chars(data)
        end
      end

      def print_chars(data)
        buf = buffer
        @unicode_handler.grapheme_clusters(data).each do |raw_ch|
          ch = translate_char(raw_ch)
          width = char_width(ch)

          if width.zero?
            append_to_previous_cell(ch)
            next
          end

          if buf.x > right_margin || buf.x + width - 1 > right_margin
            if @autowrap
              buf.get_line(buf.y)&.is_wrapped = true
              line_feed
              carriage_return
            else
              buf.x = right_margin
            end
          end

          buf.x = left_margin if @left_right_margin_mode && buf.x < left_margin

          line = buf.get_line(buf.y)
          next unless line

          line.insert_cells(buf.x, width, erase_cell) if @insert_mode && width.positive?

          @print_cell.copy_from(@cur_attr)
          @print_cell.char = ch
          @print_cell.width = width
          @print_cell.link = @current_link&.dup

          line.set_cell(buf.x, @print_cell)

          buf.x += width

          buf.x = right_margin if !@autowrap && buf.x > right_margin
          @last_printed_char = ch
        end
      end

      def append_to_previous_cell(ch)
        line, x = previous_printable_cell
        return unless line

        cell = line.get_cell(x)
        return unless cell&.has_content? && cell.width.positive?

        cell.char = cell.char + ch
      end

      def previous_printable_cell
        buf = buffer
        y = buf.y
        x = [buf.x - 1, buf.cols - 1].min

        loop do
          return nil if y.negative?

          line = buf.get_line(y)
          if line && x >= 0
            x -= 1 if x.positive? && line.get_cell(x)&.width&.zero? && line.get_cell(x - 1)&.width == 2
            cell = line.get_cell(x)
            return [line, x] if cell&.has_content? && cell.width.positive?
          end

          return nil unless y.positive? && buf.get_line(y - 1)&.is_wrapped

          y -= 1
          x = buf.cols - 1
        end
      end

      # ── CSI handlers ──

      def register_csi_handlers
        # CUU - Cursor Up
        @parser.set_csi_handler({ final: "A" }) do |params|
          n = [params[0], 1].max
          buffer.y = [buffer.y - n, buffer.scroll_top].max
        end

        # CUD - Cursor Down
        @parser.set_csi_handler({ final: "B" }) do |params|
          n = [params[0], 1].max
          buffer.y = [buffer.y + n, buffer.scroll_bottom].min
        end

        # CUF - Cursor Forward
        @parser.set_csi_handler({ final: "C" }) do |params|
          n = [params[0], 1].max
          buffer.x = [buffer.x + n, right_margin].min
        end

        # CUB - Cursor Backward
        @parser.set_csi_handler({ final: "D" }) do |params|
          n = [params[0], 1].max
          cursor_backward(n)
        end

        # CNL - Cursor Next Line
        @parser.set_csi_handler({ final: "E" }) do |params|
          n = [params[0], 1].max
          buffer.y = [buffer.y + n, buffer.rows - 1].min
          carriage_return
        end

        # CPL - Cursor Preceding Line
        @parser.set_csi_handler({ final: "F" }) do |params|
          n = [params[0], 1].max
          buffer.y = [buffer.y - n, 0].max
          carriage_return
        end

        # CUP - Cursor Position
        @parser.set_csi_handler({ final: "H" }) { |params| move_cursor_to(params) }

        # CHT - Cursor Forward Tabulation
        @parser.set_csi_handler({ final: "I" }) do |params|
          tab([params[0], 1].max)
        end

        # HVP - Horizontal Vertical Position (same as CUP)
        @parser.set_csi_handler({ final: "f" }) { |params| move_cursor_to(params) }

        # ED - Erase in Display
        @parser.set_csi_handler({ final: "J" }) do |params|
          erase_in_display(params[0])
        end

        # DECSED - Selective Erase in Display
        @parser.set_csi_handler({ prefix: "?", final: "J" }) do |params|
          erase_in_display(params[0], selective: true)
        end

        # EL - Erase in Line
        @parser.set_csi_handler({ final: "K" }) do |params|
          erase_in_line(params[0])
        end

        # DECSEL - Selective Erase in Line
        @parser.set_csi_handler({ prefix: "?", final: "K" }) do |params|
          erase_in_line(params[0], selective: true)
        end

        # IL - Insert Lines
        @parser.set_csi_handler({ final: "L" }) do |params|
          insert_lines([params[0], 1].max)
        end

        # DL - Delete Lines
        @parser.set_csi_handler({ final: "M" }) do |params|
          delete_lines([params[0], 1].max)
        end

        # DCH - Delete Characters
        @parser.set_csi_handler({ final: "P" }) do |params|
          n = [params[0], 1].max
          line = buffer.get_line(buffer.y)
          line&.delete_cells(buffer.x, n, erase_cell)
        end

        # ICH - Insert Characters
        @parser.set_csi_handler({ final: "@" }) do |params|
          n = [params[0], 1].max
          line = buffer.get_line(buffer.y)
          line&.insert_cells(buffer.x, n, erase_cell)
        end

        # SU - Scroll Up
        @parser.set_csi_handler({ final: "S" }) do |params|
          n = [params[0], 1].max
          scroll_up(n)
        end

        # SD - Scroll Down
        @parser.set_csi_handler({ final: "T" }) do |params|
          n = [params[0], 1].max
          scroll_down(n)
        end

        # ECH - Erase Characters
        @parser.set_csi_handler({ final: "X" }) do |params|
          n = [params[0], 1].max
          line = buffer.get_line(buffer.y)
          if line
            end_col = [buffer.x + n, buffer.cols].min
            line.replace_cells(buffer.x, end_col, erase_cell)
          end
        end

        # DECFRA - Fill Rectangular Area
        @parser.set_csi_handler({ intermediates: "$", final: "x" }) do |params|
          fill_rectangular_area(params)
        end

        # DECCARA - Change Attributes in Rectangular Area
        @parser.set_csi_handler({ intermediates: "$", final: "r" }) do |params|
          change_rectangular_area_attributes(params)
        end

        # DECRARA - Reverse Attributes in Rectangular Area
        @parser.set_csi_handler({ intermediates: "$", final: "t" }) do |params|
          reverse_rectangular_area_attributes(params)
        end

        # DECERA - Erase Rectangular Area
        @parser.set_csi_handler({ intermediates: "$", final: "z" }) do |params|
          erase_rectangular_area(params)
        end

        # DECSERA - Selective Erase Rectangular Area
        @parser.set_csi_handler({ intermediates: "$", final: "{" }) do |params|
          erase_rectangular_area(params, selective: true)
        end

        # SGR - Set Graphic Rendition
        @parser.set_csi_handler({ final: "m" }) do |params|
          handle_sgr(params)
        end

        # XTWINOPS - Window manipulation
        @parser.set_csi_handler({ final: "t" }) do |params|
          handle_window_operation(params)
        end

        # DSR - Device Status Report
        @parser.set_csi_handler({ final: "n" }) do |params|
          case params[0]
          when 5
            emit(:data, "\e[0n")
          when 6
            emit(:data, "\e[#{buffer.y + 1};#{buffer.x + 1}R")
          end
        end

        # DECXCPR - DEC extended cursor position report
        @parser.set_csi_handler({ prefix: "?", final: "n" }) do |params|
          emit(:data, "\e[?#{buffer.y + 1};#{buffer.x + 1}R") if params[0] == 6
        end

        # DA - Primary Device Attributes
        @parser.set_csi_handler({ final: "c" }) do |params|
          emit(:data, "\e[?1;2c") if params[0].zero?
        end

        # Secondary DA
        @parser.set_csi_handler({ prefix: ">", final: "c" }) do
          emit(:data, "\e[>0;276;0c")
        end

        # DECSTBM - Set Scrolling Region
        @parser.set_csi_handler({ final: "r" }) do |params|
          top = params[0]
          bottom = params.length > 1 ? params[1] : 0
          if top == 0 && bottom == 0
            buffer.scroll_top = 0
            buffer.scroll_bottom = buffer.rows - 1
          else
            buffer.scroll_top = [[top - 1, 0].max, buffer.rows - 1].min
            buffer.scroll_bottom = [[(bottom.zero? ? buffer.rows : bottom) - 1, 0].max, buffer.rows - 1].min
          end
          reset_cursor_to_home
        end

        # VPA - Vertical Position Absolute
        @parser.set_csi_handler({ final: "d" }) do |params|
          row = [params[0], 1].max
          buffer.y = [[row - 1, 0].max, buffer.rows - 1].min
        end

        # VPR - Vertical Position Relative
        @parser.set_csi_handler({ final: "e" }) do |params|
          row = [params[0], 1].max
          buffer.y = [buffer.y + row, buffer.rows - 1].min
        end

        # CHA - Cursor Horizontal Absolute
        @parser.set_csi_handler({ final: "G" }) do |params|
          col = [params[0], 1].max
          buffer.x = [[col - 1, left_margin].max, right_margin].min
        end

        # HPA - Horizontal Position Absolute
        @parser.set_csi_handler({ final: "`" }) do |params|
          col = [params[0], 1].max
          buffer.x = [[col - 1, left_margin].max, right_margin].min
        end

        # HPR - Horizontal Position Relative
        @parser.set_csi_handler({ final: "a" }) do |params|
          col = [params[0], 1].max
          buffer.x = [buffer.x + col, right_margin].min
        end

        # REP - Repeat Previous Character
        @parser.set_csi_handler({ final: "b" }) do |params|
          if @last_printed_char
            n = [params[0], 1].max
            print_chars(@last_printed_char * n)
          end
        end

        # TBC - Tab Clear
        @parser.set_csi_handler({ final: "g" }) do |params|
          clear_tab_stop(params[0])
        end

        # DECSCUSR - Set Cursor Style
        @parser.set_csi_handler({ intermediates: " ", final: "q" }) do |params|
          @cursor_style = cursor_style_from_param(params[0])
        end

        # DECSCA - Select Character Protection Attribute
        @parser.set_csi_handler({ intermediates: '"', final: "q" }) do |params|
          @cur_attr.protected = params[0] == 1
        end

        # CBT - Cursor Backward Tabulation
        @parser.set_csi_handler({ final: "Z" }) do |params|
          backward_tab([params[0], 1].max)
        end

        # SCP - Save Cursor
        @parser.set_csi_handler({ final: "s" }) do |params|
          if @left_right_margin_mode && (params.length > 1 || params[0].positive?)
            set_left_right_margins(params)
          else
            save_cursor_state
          end
        end

        # RCP - Restore Cursor
        @parser.set_csi_handler({ final: "u" }) do
          restore_cursor_state
        end

        # SM - Set Mode
        @parser.set_csi_handler({ final: "h" }) do |params|
          params.length.times do |i|
            set_mode(params[i])
          end
        end

        # RM - Reset Mode
        @parser.set_csi_handler({ final: "l" }) do |params|
          params.length.times do |i|
            reset_mode(params[i])
          end
        end

        # DECRQM - Request ANSI Mode
        @parser.set_csi_handler({ intermediates: "$", final: "p" }) do |params|
          report_mode(params[0], mode_status(params[0]))
        end

        # DECSM - DEC Private Mode Set (CSI ? h)
        @parser.set_csi_handler({ prefix: "?", final: "h" }) do |params|
          params.length.times do |i|
            dec_private_mode_set(params[i])
          end
        end

        # DECRM - DEC Private Mode Reset (CSI ? l)
        @parser.set_csi_handler({ prefix: "?", final: "l" }) do |params|
          params.length.times do |i|
            dec_private_mode_reset(params[i])
          end
        end

        # DECRQM - Request DEC Private Mode
        @parser.set_csi_handler({ prefix: "?", intermediates: "$", final: "p" }) do |params|
          report_mode(params[0], private_mode_status(params[0]), private_mode: true)
        end
      end

      # ── ESC handlers ──

      def register_esc_handlers
        # IND - Index
        @parser.set_esc_handler({ final: "D" }) do
          line_feed
        end

        # NEL - Next Line
        @parser.set_esc_handler({ final: "E" }) do
          line_feed
          carriage_return
        end

        # HTS - Horizontal Tab Set
        @parser.set_esc_handler({ final: "H" }) do
          set_tab_stop
        end

        # DECKPAM - Application Keypad
        @parser.set_esc_handler({ final: "=" }) do
          @application_keypad_mode = true
        end

        # DECKPNM - Numeric Keypad
        @parser.set_esc_handler({ final: ">" }) do
          @application_keypad_mode = false
        end

        # DECSC - Save Cursor
        @parser.set_esc_handler({ final: "7" }) do
          save_cursor_state
        end

        # DECRC - Restore Cursor
        @parser.set_esc_handler({ final: "8" }) do
          restore_cursor_state
        end

        # RI - Reverse Index
        @parser.set_esc_handler({ final: "M" }) do
          if buffer.y == buffer.scroll_top
            scroll_down(1)
          else
            buffer.y = [buffer.y - 1, 0].max
          end
        end

        # RIS - Full Reset
        @parser.set_esc_handler({ final: "c" }) do
          full_reset
        end

        # Charset designation for G0/G1.
        { "(" => 0, ")" => 1 }.each do |intermediate, slot|
          %w[B 0].each do |ch|
            @parser.set_esc_handler({ intermediates: intermediate, final: ch }) do
              set_charset(slot, ch)
            end
          end
        end
      end

      # ── OSC handlers ──

      def register_osc_handlers
        @parser.set_osc_handler(0) do |data|
          set_icon_name(data)
          set_title(data)
        end

        @parser.set_osc_handler(1) do |data|
          set_icon_name(data)
        end

        @parser.set_osc_handler(2) do |data|
          set_title(data)
        end

        @parser.set_osc_handler(4) do |data|
          handle_palette_osc(data)
        end

        @parser.set_osc_handler(8) do |data|
          params, uri = data.split(";", 2)
          payload = { params: params || "", uri: uri || "" }
          @current_link = payload[:uri].empty? ? nil : payload
          emit(:hyperlink, payload)
        end

        @parser.set_osc_handler(10) do |data|
          handle_dynamic_color_osc(10, :foreground, data)
        end

        @parser.set_osc_handler(11) do |data|
          handle_dynamic_color_osc(11, :background, data)
        end

        @parser.set_osc_handler(12) do |data|
          handle_dynamic_color_osc(12, :cursor, data)
        end

        @parser.set_osc_handler(52) do |data|
          handle_clipboard_osc(data)
        end

        @parser.set_osc_handler(1337) do |data|
          handle_iterm2_osc(data)
        end

        @parser.set_osc_handler(104) do |data|
          handle_palette_reset_osc(data)
        end

        @parser.set_osc_handler(110) do
          @color_manager.foreground = @color_manager.theme.foreground
        end

        @parser.set_osc_handler(111) do
          @color_manager.background = @color_manager.theme.background
        end

        @parser.set_osc_handler(112) do
          @color_manager.cursor = @color_manager.theme.cursor
        end
      end

      def register_dcs_handlers
        @parser.set_dcs_handler({ intermediates: "$", final: "q" }) do |data, _params|
          emit(:data, decrqss_response(data))
        end

        @parser.set_dcs_handler({ final: "q" }) do |data, params|
          sixel_params = dcs_params_array(params)
          payload = SixelParser.parse(data, params: sixel_params)
          record_image(payload, raw_sequence: sixel_sequence(sixel_params, data))
        end
      end

      # ── Cursor movement helpers ──

      def cursor_backward(n)
        n.times do
          if buffer.x > left_margin
            buffer.x -= 1
          elsif @reverse_wraparound && buffer.y.positive? && !@left_right_margin_mode
            buffer.y -= 1
            buffer.x = reverse_wrap_column(buffer.get_line(buffer.y))
          end
        end
      end

      def reverse_wrap_column(line)
        return buffer.cols - 1 if line&.is_wrapped

        trimmed = line&.get_trimmed_length.to_i
        return buffer.cols - 1 if trimmed.zero?

        [[trimmed - 1, 0].max, buffer.cols - 1].min
      end

      def tab(count = 1)
        buf = buffer
        count.times do
          buf.x = next_tab_stop(buf, buf.x)
        end
      end

      def backward_tab(count = 1)
        buf = buffer
        count.times do
          buf.x = previous_tab_stop(buf, buf.x)
        end
      end

      def line_feed
        buf = buffer
        if buf.y == buf.scroll_bottom
          scroll_up(1)
        else
          buf.y += 1
        end
        emit(:line_feed)
      end

      def carriage_return
        buffer.x = left_margin
      end

      # ── Scroll helpers ──

      def scroll_up(count)
        buf = buffer
        if buf.scroll_top.zero? && buf.scroll_bottom == buf.rows - 1
          buf.scroll_up(count)
          return
        end

        count.times do
          top = buf.scroll_top + buf.y_base
          bottom = buf.scroll_bottom + buf.y_base

          (top...bottom).each do |i|
            src = buf.lines[i + 1]
            buf.lines[i] = src.clone if src
          end
          buf.lines[bottom] = BufferLine.new(buf.cols)
        end
      end

      def scroll_down(count)
        buf = buffer
        count.times do
          top = buf.scroll_top + buf.y_base
          bottom = buf.scroll_bottom + buf.y_base

          bottom.downto(top + 1) do |i|
            src = buf.lines[i - 1]
            buf.lines[i] = src.clone if src
          end
          buf.lines[top] = BufferLine.new(buf.cols)
        end
      end

      def set_left_right_margins(params)
        left = [params[0], 1].max
        right = params.length > 1 && params[1].positive? ? params[1] : buffer.cols
        left = [[left - 1, 0].max, buffer.cols - 1].min
        right = [[right - 1, 0].max, buffer.cols - 1].min
        return if left >= right

        @left_margin = left
        @right_margin = right
        reset_cursor_to_home
      end

      # ── Cursor position helper ──

      def move_cursor_to(params)
        row = [params[0], 1].max
        col = params.length > 1 ? [params[1], 1].max : 1
        top = @origin_mode ? buffer.scroll_top : 0
        bottom = @origin_mode ? buffer.scroll_bottom : buffer.rows - 1
        left = @origin_mode ? left_margin : 0
        right = @left_right_margin_mode ? right_margin : buffer.cols - 1
        buffer.y = [[top + row - 1, top].max, bottom].min
        buffer.x = [[left + col - 1, left].max, right].min
      end

      # ── Erase helpers ──

      def erase_cell
        @erase_cell.fg = @cur_attr.fg & ~(BufferConstants::FgFlags::BOLD |
                                          BufferConstants::FgFlags::UNDERLINE |
                                          BufferConstants::FgFlags::BLINK |
                                          BufferConstants::FgFlags::INVERSE |
                                          BufferConstants::FgFlags::INVISIBLE |
                                          BufferConstants::FgFlags::STRIKETHROUGH)
        @erase_cell.bg = @cur_attr.bg & ~(BufferConstants::BgFlags::ITALIC |
                                          BufferConstants::BgFlags::DIM |
                                          BufferConstants::BgFlags::OVERLINE)
        @erase_cell
      end

      def erase_in_display(mode, selective: false)
        buf = buffer
        case mode
        when 0
          # Erase from cursor to end of display
          line = buf.get_line(buf.y)
          replace_cells(line, buf.x, buf.cols, erase_cell, selective: selective)
          ((buf.y + 1)...buf.rows).each do |y|
            replace_cells(buf.get_line(y), 0, buf.cols, erase_cell, selective: selective)
          end
        when 1
          # Erase from start of display to cursor
          (0...buf.y).each do |y|
            replace_cells(buf.get_line(y), 0, buf.cols, erase_cell, selective: selective)
          end
          line = buf.get_line(buf.y)
          replace_cells(line, 0, buf.x + 1, erase_cell, selective: selective)
        when 2
          # Erase entire display
          buf.rows.times do |y|
            replace_cells(buf.get_line(y), 0, buf.cols, erase_cell, selective: selective)
          end
        when 3
          # Erase scrollback
          buf.clear unless selective
        end
      end

      def erase_in_line(mode, selective: false)
        buf = buffer
        line = buf.get_line(buf.y)
        return unless line

        case mode
        when 0
          replace_cells(line, buf.x, buf.cols, erase_cell, selective: selective)
        when 1
          replace_cells(line, 0, buf.x + 1, erase_cell, selective: selective)
        when 2
          replace_cells(line, 0, buf.cols, erase_cell, selective: selective)
        end
      end

      def replace_cells(line, start_col, end_col, fill, selective: false)
        return unless line

        if selective
          start_col = [[start_col, 0].max, line.length].min
          end_col = [[end_col, 0].max, line.length].min
          (start_col...end_col).each do |x|
            next if line.get_cell(x)&.protected?

            line.set_cell(x, fill)
          end
        else
          line.replace_cells(start_col, end_col, fill)
        end
      end

      def erase_rectangular_area(params, selective: false)
        each_rectangular_cell(params) do |line, x|
          next if selective && line.get_cell(x)&.protected?

          line.set_cell(x, erase_cell)
        end
      end

      def fill_rectangular_area(params)
        fill = CellData.new
        fill.copy_from(@cur_attr)
        fill.char = fill_char_from_param(params[0])
        fill.width = 1

        each_rectangular_cell(params, offset: 1) do |line, x|
          line.set_cell(x, fill)
        end
      end

      def change_rectangular_area_attributes(params)
        attrs = rectangular_attribute_params(params)
        each_rectangular_cell(params) do |line, x|
          cell = line.get_cell(x)
          apply_sgr_to_attr(cell, attrs) if cell
        end
      end

      def reverse_rectangular_area_attributes(params)
        attrs = rectangular_attribute_params(params)
        each_rectangular_cell(params) do |line, x|
          cell = line.get_cell(x)
          reverse_sgr_on_attr(cell, attrs) if cell
        end
      end

      def each_rectangular_cell(params, offset: 0)
        top, left, bottom, right = rectangular_area(params, offset)
        (top..bottom).each do |y|
          line = buffer.get_line(y)
          next unless line

          (left..right).each { |x| yield line, x, y }
        end
      end

      def rectangular_area(params, offset)
        top = positive_param(params, offset, 1)
        left = positive_param(params, offset + 1, 1)
        bottom = positive_param(params, offset + 2, buffer.rows)
        right = positive_param(params, offset + 3, buffer.cols)

        top = [[top - 1, 0].max, buffer.rows - 1].min
        left = [[left - 1, 0].max, buffer.cols - 1].min
        bottom = [[bottom - 1, top].max, buffer.rows - 1].min
        right = [[right - 1, left].max, buffer.cols - 1].min
        [top, left, bottom, right]
      end

      def positive_param(params, index, default)
        return default if index >= params.length || params[index].zero?

        [params[index], 1].max
      end

      def rectangular_attribute_params(params)
        values = []
        4.upto(params.length - 1) { |index| values << params[index] }
        values.empty? ? [0] : values
      end

      def fill_char_from_param(value)
        return " " if value.to_i.zero?

        char = value.to_i.chr(Encoding::UTF_8)
        char_width(char) == 1 ? char : " "
      rescue RangeError
        " "
      end

      # ── Insert/Delete lines ──

      def insert_lines(count)
        buf = buffer
        bottom = buf.scroll_bottom + buf.y_base
        row = buf.y + buf.y_base

        count.times do
          bottom.downto(row + 1) do |i|
            src = buf.lines[i - 1]
            buf.lines[i] = src.clone if src
          end
          buf.lines[row] = BufferLine.new(buf.cols)
        end
      end

      def delete_lines(count)
        buf = buffer
        bottom = buf.scroll_bottom + buf.y_base
        row = buf.y + buf.y_base

        count.times do
          (row...bottom).each do |i|
            src = buf.lines[i + 1]
            buf.lines[i] = src.clone if src
          end
          buf.lines[bottom] = BufferLine.new(buf.cols)
        end
      end

      # ── SGR ──

      def handle_sgr(params)
        apply_sgr_to_attr(@cur_attr, params)
      end

      def apply_sgr_to_attr(attr, params)
        i = 0
        while i < params.length
          p = params[i]
          case p
          when 0
            attr.reset
          when 1
            attr.bold = true
          when 2
            attr.dim = true
          when 3
            attr.italic = true
          when 4
            attr.underline = true
          when 5
            attr.blink = true
          when 7
            attr.inverse = true
          when 8
            attr.invisible = true
          when 9
            attr.strikethrough = true
          when 22
            attr.bold = false
            attr.dim = false
          when 23
            attr.italic = false
          when 24
            attr.underline = false
          when 25
            attr.blink = false
          when 27
            attr.inverse = false
          when 28
            attr.invisible = false
          when 29
            attr.strikethrough = false
          when 30..37
            attr.set_fg_color(:p16, p - 30)
          when 38
            i = handle_extended_color(attr, params, i, :fg)
          when 39
            attr.reset_fg_color
          when 40..47
            attr.set_bg_color(:p16, p - 40)
          when 48
            i = handle_extended_color(attr, params, i, :bg)
          when 49
            attr.reset_bg_color
          when 53
            attr.overline = true
          when 55
            attr.overline = false
          when 90..97
            attr.set_fg_color(:p16, p - 90 + 8)
          when 100..107
            attr.set_bg_color(:p16, p - 100 + 8)
          end
          i += 1
        end
      end

      def reverse_sgr_on_attr(attr, params)
        params.each do |p|
          case p
          when 1 then attr.bold = !attr.bold?
          when 2 then attr.dim = !attr.dim?
          when 3 then attr.italic = !attr.italic?
          when 4 then attr.underline = !attr.underline?
          when 5 then attr.blink = !attr.blink?
          when 7 then attr.inverse = !attr.inverse?
          when 8 then attr.invisible = !attr.invisible?
          when 9 then attr.strikethrough = !attr.strikethrough?
          when 53 then attr.overline = !attr.overline?
          end
        end
      end

      def handle_extended_color(attr, params, i, target)
        if i + 1 < params.length && params[i + 1] == 5
          # 256 color: 38;5;N or 48;5;N
          if i + 2 < params.length
            color = params[i + 2]
            if target == :fg
              attr.set_fg_color(:p256, color)
            else
              attr.set_bg_color(:p256, color)
            end
            return i + 2
          end
        elsif i + 1 < params.length && params[i + 1] == 2
          # TrueColor: 38;2;R;G;B or 48;2;R;G;B
          if i + 4 < params.length
            r = params[i + 2]
            g = params[i + 3]
            b = params[i + 4]
            rgb = (r << 16) | (g << 8) | b
            if target == :fg
              attr.set_fg_color(:rgb, rgb)
            else
              attr.set_bg_color(:rgb, rgb)
            end
            return i + 4
          end
        end
        i
      end

      # ── Mode reports ──

      def report_mode(mode, status, private_mode: false)
        prefix = private_mode ? "?" : ""
        emit(:data, "\e[#{prefix}#{mode};#{status}$y")
      end

      def mode_status(mode)
        case mode
        when 4
          @insert_mode ? 1 : 2
        else
          0
        end
      end

      def private_mode_status(mode)
        case mode
        when 1
          @application_cursor_keys_mode ? 1 : 2
        when 6
          @origin_mode ? 1 : 2
        when 7
          @autowrap ? 1 : 2
        when 12
          @cursor_blink ? 1 : 2
        when 25
          @cursor_hidden ? 2 : 1
        when 45
          @reverse_wraparound ? 1 : 2
        when 69
          @left_right_margin_mode ? 1 : 2
        when 66
          @application_keypad_mode ? 1 : 2
        when 9, 1000
          @mouse_tracking_mode == :x10 ? 1 : 2
        when 1002
          @mouse_tracking_mode == :button ? 1 : 2
        when 1003
          @mouse_tracking_mode == :any ? 1 : 2
        when 1004
          @focus_event_mode ? 1 : 2
        when 1005
          @utf8_mouse_mode ? 1 : 2
        when 1006
          @sgr_mouse_mode ? 1 : 2
        when 1015
          @urxvt_mouse_mode ? 1 : 2
        when 47, 1047, 1049
          @buffer_set.active.equal?(@buffer_set.alt) ? 1 : 2
        when 2004
          @bracketed_paste_mode ? 1 : 2
        else
          0
        end
      end

      # ── DEC Private Modes ──

      def dec_private_mode_set(mode)
        case mode
        when 1
          @application_cursor_keys_mode = true
        when 6
          @origin_mode = true
          reset_cursor_to_home
        when 7
          @autowrap = true
        when 12
          @cursor_blink = true
        when 25
          @cursor_hidden = false
        when 45
          @reverse_wraparound = true
        when 69
          @left_right_margin_mode = true
          @left_margin = 0
          @right_margin = buffer.cols - 1
          reset_cursor_to_home
        when 66
          @application_keypad_mode = true
        when 9
          @mouse_tracking_mode = :x10
        when 1000
          @mouse_tracking_mode = :x10
        when 1002
          @mouse_tracking_mode = :button
        when 1003
          @mouse_tracking_mode = :any
        when 1004
          @focus_event_mode = true
        when 1005
          @utf8_mouse_mode = true
        when 1006
          @sgr_mouse_mode = true
        when 1015
          @urxvt_mouse_mode = true
        when 47, 1047
          @buffer_set.activate_alt_buffer(clear: true)
        when 1048
          save_cursor_state
        when 1049
          save_cursor_state
          @buffer_set.activate_alt_buffer(clear: true)
        when 2004
          @bracketed_paste_mode = true
        end
      end

      def dec_private_mode_reset(mode)
        case mode
        when 1
          @application_cursor_keys_mode = false
        when 6
          @origin_mode = false
          reset_cursor_to_home
        when 7
          @autowrap = false
        when 12
          @cursor_blink = false
        when 25
          @cursor_hidden = true
        when 45
          @reverse_wraparound = false
        when 69
          @left_right_margin_mode = false
          @left_margin = 0
          @right_margin = buffer.cols - 1
          reset_cursor_to_home
        when 66
          @application_keypad_mode = false
        when 9, 1000, 1002, 1003
          @mouse_tracking_mode = nil
        when 1004
          @focus_event_mode = false
        when 1005
          @utf8_mouse_mode = false
        when 1006
          @sgr_mouse_mode = false
        when 1015
          @urxvt_mouse_mode = false
        when 47, 1047
          @buffer_set.activate_normal_buffer
        when 1048
          restore_cursor_state
        when 1049
          @buffer_set.activate_normal_buffer
          restore_cursor_state
        when 2004
          @bracketed_paste_mode = false
        end
      end

      # ── Full Reset ──

      def full_reset
        buf = buffer
        buf.x = 0
        buf.y = 0
        buf.scroll_top = 0
        buf.scroll_bottom = buf.rows - 1
        @cur_attr = CellData.new
        @autowrap = true
        @cursor_hidden = false
        @cursor_blink = @default_cursor_blink
        @cursor_style = @default_cursor_style
        @bracketed_paste_mode = false
        @insert_mode = false
        @origin_mode = false
        @application_cursor_keys_mode = false
        @application_keypad_mode = false
        @reverse_wraparound = false
        @focus_event_mode = false
        @mouse_tracking_mode = nil
        @sgr_mouse_mode = false
        @utf8_mouse_mode = false
        @urxvt_mouse_mode = false
        @left_right_margin_mode = false
        @left_margin = 0
        @right_margin = buf.cols - 1
        @color_manager.reset_defaults
        @color_manager.reset_ansi_color
        @clipboard.clear
        @images.clear
        @title = ""
        @icon_name = ""
        @current_link = nil
        @charset_g = 0
        @charsets = [Charsets.fetch(:ascii), Charsets.fetch(:ascii)]
        @last_printed_char = nil
        buf.rows.times do |y|
          buf.get_line(y)&.replace_cells(0, buf.cols, CellData.new)
        end
      end

      # ── Character width ──

      def char_width(ch)
        @unicode_handler.char_width(ch)
      end

      def translate_char(ch)
        @charsets.fetch(@charset_g, Charsets.fetch(:ascii)).translate(ch)
      end

      def set_charset(slot, charset)
        @charsets[slot] = Charsets.fetch(charset)
      end

      def set_title(value)
        @title = value.to_s
        emit(:title_change, @title)
      end

      def set_icon_name(value)
        @icon_name = value.to_s
        emit(:icon_name_change, @icon_name)
      end

      def handle_window_operation(params)
        values = params.to_array
        operation = values.first.to_i
        emit(:window_operation, { operation: operation, params: values })

        case operation
        when 18, 19
          emit(:data, "\e[8;#{buffer.rows};#{buffer.cols}t")
        when 20
          emit(:data, "\e]L#{@icon_name}\a")
        when 21
          emit(:data, "\e]l#{@title}\a")
        end
      end

      def handle_palette_osc(data)
        parts = data.split(";")
        parts.each_slice(2) do |index, color|
          next if index.nil? || color.nil?

          if color == "?"
            emit(:data, "\e]4;#{index};#{osc_color_spec(@color_manager.palette[index.to_i])}\a")
          else
            @color_manager.set_ansi_color(index.to_i, color)
          end
        end
      end

      def handle_dynamic_color_osc(id, target, data)
        if data == "?"
          emit(:data, "\e]#{id};#{osc_color_spec(@color_manager.public_send(target))}\a")
        else
          @color_manager.public_send("#{target}=", data)
        end
      end

      def handle_clipboard_osc(data)
        selection, encoded = data.split(";", 2)
        selection ||= ""
        encoded ||= ""

        if encoded == "?"
          emit(:clipboard_request, { selection: selection, selections: clipboard_selections(selection) })
          respond_to_clipboard_query(selection)
          return
        end

        decoded = decode_clipboard_data(encoded)
        payload = {
          selection: selection,
          selections: clipboard_selections(selection),
          data: encoded,
          decoded: decoded,
          multipart: multipart_clipboard_data?(encoded),
          chunks: clipboard_data_chunks(encoded)
        }
        allowed, reason = clipboard_write_allowed?(payload)
        payload[:allowed] = allowed
        payload[:reason] = reason if reason
        store_clipboard_data(payload[:selections], decoded) if allowed && decoded
        emit(:clipboard, payload)
      end

      def respond_to_clipboard_query(selection)
        selections = clipboard_selections(selection)
        value = clipboard_query_value(selections)
        return unless value

        encoded = encode_clipboard_data(value)
        emit(:data, "\e]52;#{selection};#{encoded}\a")
      end

      def clipboard_write_allowed?(payload)
        return [false, :disabled] unless @clipboard_enabled
        return [false, :invalid_base64] unless payload[:decoded]
        return [false, :too_large] if payload[:decoded].bytesize > @clipboard_max_bytes

        if @clipboard_write_handler.respond_to?(:call)
          return [false, :denied] unless @clipboard_write_handler.call(payload)
        end

        [true, nil]
      end

      def clipboard_query_value(selections)
        selections.each do |name|
          value = @clipboard[name]
          return value if value
        end

        return unless @clipboard_enabled && @clipboard_read_handler.respond_to?(:call)

        @clipboard_read_handler.call(selections)
      end

      def store_clipboard_data(selections, decoded)
        selections.each { |name| @clipboard[name] = decoded }
      end

      def clipboard_selections(selection)
        chars = selection.to_s.empty? ? ["c"] : selection.to_s.chars
        chars.map { |name| clipboard_selection_alias(name) }
      end

      def clipboard_selection_alias(name)
        case name
        when "c" then "clipboard"
        when "p" then "primary"
        when "q" then "secondary"
        when "s" then "select"
        when "0".."7" then "cut#{name}"
        else name
        end
      end

      def decode_clipboard_data(encoded)
        return "" if encoded.empty?

        parts = encoded.split(";", -1)
        return nil if parts.any?(&:empty?)

        joined = parts.join
        return nil unless joined.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/) && (joined.length % 4).zero?

        joined.unpack1("m0").force_encoding("UTF-8").scrub
      rescue ArgumentError
        nil
      end

      def multipart_clipboard_data?(encoded)
        encoded.include?(";")
      end

      def clipboard_data_chunks(encoded)
        return 1 if encoded.empty?

        encoded.split(";", -1).length
      end

      def encode_clipboard_data(value)
        [value].pack("m0")
      end

      def osc_color_spec(color)
        value = color.to_s
        return value if value.start_with?("rgb:")

        hex = value.delete_prefix("#")
        return value unless hex.match?(/\A[0-9a-fA-F]{6}\z/)

        red = hex[0, 2]
        green = hex[2, 2]
        blue = hex[4, 2]
        "rgb:#{red}#{red}/#{green}#{green}/#{blue}#{blue}".downcase
      end

      def handle_palette_reset_osc(data)
        indexes = data.to_s.split(";").reject(&:empty?)
        if indexes.empty?
          @color_manager.reset_ansi_color
        else
          indexes.each { |index| @color_manager.reset_ansi_color(index.to_i) }
        end
      end

      def handle_iterm2_osc(data)
        header, encoded = data.split(":", 2)
        return unless header&.start_with?("File=")

        params = header.delete_prefix("File=")
        record_image(
          {
            protocol: :iterm2,
            params: params,
            attributes: parse_iterm2_attributes(params),
            data: encoded || ""
          },
          raw_sequence: "\e]1337;File=#{params}:#{encoded || ""}\a"
        )
      end

      def record_image(payload, raw_sequence:)
        image = payload.merge(
          placement: {
            buffer: @buffer_set.active.equal?(@buffer_set.alt) ? :alt : :normal,
            row: buffer.y_base + buffer.y,
            col: buffer.x
          },
          raw_sequence: raw_sequence
        )
        @images << image
        emit(:image, image)
      end

      def sixel_sequence(params, data)
        prefix = params.empty? ? "" : params.join(";")
        "\eP#{prefix}q#{data}\e\\"
      end

      def parse_iterm2_attributes(params)
        params.to_s.split(";").each_with_object({}) do |part, attrs|
          key, value = part.split("=", 2)
          next if key.to_s.empty?

          attrs[key] = value || ""
        end
      end

      def dcs_params_array(params)
        values = params.to_array
        values == [0] ? [] : values
      end

      def decrqss_response(request)
        case request
        when " q"
          "\eP1$r#{cursor_style_param} q\e\\"
        when '"q'
          "\eP1$r#{@cur_attr.protected? ? 1 : 0}\"q\e\\"
        when "m"
          "\eP1$r#{current_sgr_params.join(';')}m\e\\"
        when "r"
          "\eP1$r#{buffer.scroll_top + 1};#{buffer.scroll_bottom + 1}r\e\\"
        when "s"
          "\eP1$r#{left_margin + 1};#{right_margin + 1}s\e\\"
        else
          "\eP0$r#{request}\e\\"
        end
      end

      def current_sgr_params
        params = []
        params << 1 if @cur_attr.bold?
        params << 2 if @cur_attr.dim?
        params << 3 if @cur_attr.italic?
        params << 4 if @cur_attr.underline?
        params << 5 if @cur_attr.blink?
        params << 7 if @cur_attr.inverse?
        params << 8 if @cur_attr.invisible?
        params << 9 if @cur_attr.strikethrough?
        params.empty? ? [0] : params
      end

      def save_cursor_state(target_buffer = buffer)
        target_buffer.save_cursor(@cur_attr)
      end

      def restore_cursor_state(target_buffer = buffer)
        restored_attr = target_buffer.restore_cursor
        @cur_attr = restored_attr if restored_attr
      end

      def set_mode(mode)
        case mode
        when 4
          @insert_mode = true
        end
      end

      def reset_mode(mode)
        case mode
        when 4
          @insert_mode = false
        end
      end

      def reset_cursor_to_home
        buffer.x = left_margin
        buffer.y = @origin_mode ? buffer.scroll_top : 0
      end

      def cursor_style_from_param(value)
        case value.to_i
        when 1 then :blinking_block
        when 2 then :block
        when 3 then :blinking_underline
        when 4 then :underline
        when 5 then :blinking_bar
        when 6 then :bar
        else :block
        end
      end

      def cursor_style_param
        case @cursor_style
        when :blinking_block then 1
        when :block then 2
        when :blinking_underline then 3
        when :underline then 4
        when :blinking_bar then 5
        when :bar then 6
        else 2
        end
      end

      def set_tab_stop
        buffer.tabs[buffer.x] = true
      end

      def clear_tab_stop(mode)
        case mode
        when 0
          buffer.tabs.delete(buffer.x)
        when 3
          buffer.tabs.clear
        end
      end

      def next_tab_stop(buf, from)
        next_stop = from + 1
        while next_stop < buf.cols
          return next_stop if buf.tabs[next_stop]

          next_stop += 1
        end
        buf.cols - 1
      end

      def previous_tab_stop(buf, from)
        previous_stop = [from - 1, 0].max
        while previous_stop > 0
          return previous_stop if buf.tabs[previous_stop]

          previous_stop -= 1
        end
        0
      end

      def mouse_button_code(button, event, modifiers)
        base = case button
               when :left then 0
               when :middle then 1
               when :right then 2
               when :release then 3
               when :wheel_up then 64
               when :wheel_down then 65
               else button.to_i
               end
        base += 32 if event == :motion
        base + mouse_modifier_code(modifiers)
      end

      def mouse_modifier_code(modifiers)
        modifiers.sum do |modifier|
          case modifier
          when :shift then 4
          when :meta, :alt then 8
          when :ctrl, :control then 16
          else 0
          end
        end
      end

      def sgr_mouse_report(code, col, row, event)
        suffix = event == :release ? "m" : "M"
        "\e[<#{code};#{col + 1};#{row + 1}#{suffix}"
      end

      def urxvt_mouse_report(code, col, row)
        "\e[#{code + 32};#{col + 1};#{row + 1}M"
      end

      def x10_mouse_report(code, col, row)
        "\e[M#{[code + 32, col + 33, row + 33].pack('U*')}"
      end
    end
  end
end
