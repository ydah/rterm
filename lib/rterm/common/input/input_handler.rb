# frozen_string_literal: true

require_relative "../event_emitter"
require_relative "../buffer/constants"
require_relative "../buffer/cell_data"

module RTerm
  module Common
    class InputHandler
      include EventEmitter
      include BufferConstants

      attr_reader :autowrap, :cursor_hidden, :bracketed_paste_mode, :insert_mode,
                  :origin_mode, :application_cursor_keys_mode, :application_keypad_mode

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
        @bracketed_paste_mode = false
        @insert_mode = false
        @origin_mode = false
        @application_cursor_keys_mode = false
        @application_keypad_mode = false
        @last_printed_char = nil
        @erase_cell = CellData.new
        @print_cell = CellData.new
        @spacer_cell = CellData.new.tap { |c| c.width = 0 }

        register_handlers
      end

      def modes
        {
          application_cursor_keys_mode: @application_cursor_keys_mode,
          application_keypad_mode: @application_keypad_mode,
          bracketed_paste_mode: @bracketed_paste_mode,
          insert_mode: @insert_mode,
          origin_mode: @origin_mode,
          wraparound_mode: @autowrap
        }
      end

      private

      def buffer
        @buffer_set.active
      end

      def register_handlers
        register_c0_handlers
        register_print_handler
        register_csi_handlers
        register_esc_handlers
        register_osc_handlers
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
        data.each_char do |ch|
          width = char_width(ch)

          if buf.x >= buf.cols
            if @autowrap
              buf.get_line(buf.y)&.is_wrapped = true
              line_feed
              carriage_return
            else
              buf.x = buf.cols - 1
            end
          end

          line = buf.get_line(buf.y)
          next unless line

          line.insert_cells(buf.x, width, erase_cell) if @insert_mode && width.positive?

          @print_cell.copy_from(@cur_attr)
          @print_cell.char = ch
          @print_cell.width = width

          line.set_cell(buf.x, @print_cell)

          if width == 2 && buf.x + 1 < buf.cols
            line.set_cell(buf.x + 1, @spacer_cell)
          end

          buf.x += width

          buf.x = buf.cols - 1 if !@autowrap && buf.x >= buf.cols
          @last_printed_char = ch
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
          buffer.x = [buffer.x + n, buffer.cols - 1].min
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

        # EL - Erase in Line
        @parser.set_csi_handler({ final: "K" }) do |params|
          erase_in_line(params[0])
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

        # SGR - Set Graphic Rendition
        @parser.set_csi_handler({ final: "m" }) do |params|
          handle_sgr(params)
        end

        # DSR - Device Status Report
        @parser.set_csi_handler({ final: "n" }) do |params|
          if params[0] == 6
            emit(:data, "\e[#{buffer.y + 1};#{buffer.x + 1}R")
          end
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
          buffer.x = [[col - 1, 0].max, buffer.cols - 1].min
        end

        # HPA - Horizontal Position Absolute
        @parser.set_csi_handler({ final: "`" }) do |params|
          col = [params[0], 1].max
          buffer.x = [[col - 1, 0].max, buffer.cols - 1].min
        end

        # HPR - Horizontal Position Relative
        @parser.set_csi_handler({ final: "a" }) do |params|
          col = [params[0], 1].max
          buffer.x = [buffer.x + col, buffer.cols - 1].min
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

        # CBT - Cursor Backward Tabulation
        @parser.set_csi_handler({ final: "Z" }) do |params|
          backward_tab([params[0], 1].max)
        end

        # SCP - Save Cursor
        @parser.set_csi_handler({ final: "s" }) do
          save_cursor_state
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

        # Charset designation
        %w[B 0].each do |ch|
          @parser.set_esc_handler({ intermediates: "(", final: ch }) do
            # charset designation — placeholder
          end
        end
      end

      # ── OSC handlers ──

      def register_osc_handlers
        @parser.set_osc_handler(0) do |data|
          emit(:title_change, data)
        end

        @parser.set_osc_handler(2) do |data|
          emit(:title_change, data)
        end
      end

      # ── Cursor movement helpers ──

      def cursor_backward(n)
        buffer.x = [buffer.x - n, 0].max
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
        buffer.x = 0
      end

      # ── Scroll helpers ──

      def scroll_up(count)
        buf = buffer
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

      # ── Cursor position helper ──

      def move_cursor_to(params)
        row = [params[0], 1].max
        col = params.length > 1 ? [params[1], 1].max : 1
        top = @origin_mode ? buffer.scroll_top : 0
        bottom = @origin_mode ? buffer.scroll_bottom : buffer.rows - 1
        buffer.y = [[top + row - 1, top].max, bottom].min
        buffer.x = [[col - 1, 0].max, buffer.cols - 1].min
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

      def erase_in_display(mode)
        buf = buffer
        case mode
        when 0
          # Erase from cursor to end of display
          line = buf.get_line(buf.y)
          line&.replace_cells(buf.x, buf.cols, erase_cell)
          ((buf.y + 1)...buf.rows).each do |y|
            buf.get_line(y)&.replace_cells(0, buf.cols, erase_cell)
          end
        when 1
          # Erase from start of display to cursor
          (0...buf.y).each do |y|
            buf.get_line(y)&.replace_cells(0, buf.cols, erase_cell)
          end
          line = buf.get_line(buf.y)
          line&.replace_cells(0, buf.x + 1, erase_cell)
        when 2
          # Erase entire display
          buf.rows.times do |y|
            buf.get_line(y)&.replace_cells(0, buf.cols, erase_cell)
          end
        when 3
          # Erase scrollback
          buf.clear
        end
      end

      def erase_in_line(mode)
        buf = buffer
        line = buf.get_line(buf.y)
        return unless line

        case mode
        when 0
          line.replace_cells(buf.x, buf.cols, erase_cell)
        when 1
          line.replace_cells(0, buf.x + 1, erase_cell)
        when 2
          line.replace_cells(0, buf.cols, erase_cell)
        end
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
        i = 0
        while i < params.length
          p = params[i]
          case p
          when 0
            @cur_attr.reset
          when 1
            @cur_attr.bold = true
          when 2
            @cur_attr.dim = true
          when 3
            @cur_attr.italic = true
          when 4
            @cur_attr.underline = true
          when 5
            @cur_attr.blink = true
          when 7
            @cur_attr.inverse = true
          when 8
            @cur_attr.invisible = true
          when 9
            @cur_attr.strikethrough = true
          when 22
            @cur_attr.bold = false
            @cur_attr.dim = false
          when 23
            @cur_attr.italic = false
          when 24
            @cur_attr.underline = false
          when 25
            @cur_attr.blink = false
          when 27
            @cur_attr.inverse = false
          when 28
            @cur_attr.invisible = false
          when 29
            @cur_attr.strikethrough = false
          when 30..37
            @cur_attr.set_fg_color(:p16, p - 30)
          when 38
            i = handle_extended_color(params, i, :fg)
          when 39
            @cur_attr.reset_fg_color
          when 40..47
            @cur_attr.set_bg_color(:p16, p - 40)
          when 48
            i = handle_extended_color(params, i, :bg)
          when 49
            @cur_attr.reset_bg_color
          when 53
            @cur_attr.overline = true
          when 55
            @cur_attr.overline = false
          when 90..97
            @cur_attr.set_fg_color(:p16, p - 90 + 8)
          when 100..107
            @cur_attr.set_bg_color(:p16, p - 100 + 8)
          end
          i += 1
        end
      end

      def handle_extended_color(params, i, target)
        if i + 1 < params.length && params[i + 1] == 5
          # 256 color: 38;5;N or 48;5;N
          if i + 2 < params.length
            color = params[i + 2]
            if target == :fg
              @cur_attr.set_fg_color(:p256, color)
            else
              @cur_attr.set_bg_color(:p256, color)
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
              @cur_attr.set_fg_color(:rgb, rgb)
            else
              @cur_attr.set_bg_color(:rgb, rgb)
            end
            return i + 4
          end
        end
        i
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
        when 25
          @cursor_hidden = false
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
        when 25
          @cursor_hidden = true
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
        @bracketed_paste_mode = false
        @insert_mode = false
        @origin_mode = false
        @application_cursor_keys_mode = false
        @application_keypad_mode = false
        @last_printed_char = nil
        buf.rows.times do |y|
          buf.get_line(y)&.replace_cells(0, buf.cols, CellData.new)
        end
      end

      # ── Character width ──

      def char_width(ch)
        @unicode_handler.char_width(ch.ord)
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
        buffer.x = 0
        buffer.y = @origin_mode ? buffer.scroll_top : 0
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
    end
  end
end
