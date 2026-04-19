# frozen_string_literal: true

require_relative "headless/headless_terminal"

module RTerm
  # Main public API for the terminal emulator.
  # Wraps HeadlessTerminal with a user-friendly interface.
  class Terminal
    # @param options [Hash] terminal options
    # @option options [Integer] :cols (80) number of columns
    # @option options [Integer] :rows (24) number of rows
    # @option options [Integer] :scrollback (1000) scrollback buffer size
    def initialize(options = {})
      @terminal = Headless::HeadlessTerminal.new(options)
      @addons = []
      @selection = nil
    end

    # @return [Integer] number of columns
    def cols
      @terminal.cols
    end

    # @return [Integer] number of rows
    def rows
      @terminal.rows
    end

    # --- Data I/O ---

    # Writes data to the terminal (as if received from PTY).
    # @param data [String] the data to write
    def write(data)
      @terminal.write(data)
    end

    # Writes data followed by a carriage return and newline.
    # @param data [String] the data to write
    def writeln(data)
      @terminal.writeln(data)
    end

    # Simulates user input (sends data event for PTY forwarding).
    # @param data [String] the input data
    def input(data)
      return if options.disable_stdin

      scroll_to_bottom if options.scroll_on_user_input
      @terminal.emit(:data, data)
      data
    end

    # Simulates binary user input for protocols that bypass UTF-8 text paths.
    # @param data [String] binary input data
    # @return [String, nil]
    def binary(data)
      return if options.disable_stdin

      payload = data.to_s.b
      scroll_to_bottom if options.scroll_on_user_input
      @terminal.emit(:binary, payload)
      payload
    end

    # Simulates paste input, honoring bracketed paste mode when enabled.
    # @param data [String] pasted text
    # @return [String, nil] emitted payload
    def paste(data)
      payload = data.to_s
      payload = "\e[200~#{payload}\e[201~" if modes[:bracketed_paste_mode]
      input(payload)
    end

    # Encodes and emits a high-level key event as terminal input.
    # @param key [Symbol, String]
    # @param modifiers [Array<Symbol>]
    # @param text [String, nil]
    # @return [String, nil]
    def key_event(key, modifiers: [], text: nil)
      encoded = Common::KeyEncoder.new(modes).encode(key, modifiers: modifiers, text: text)
      input(encoded) if encoded
    end

    # --- Buffer Access ---

    # Returns the buffer namespace for accessing buffer content.
    # @return [BufferNamespace]
    def buffer
      @buffer_namespace ||= BufferNamespace.new(@terminal.buffer_set)
    end

    # Returns parser hooks for custom escape sequence handling.
    # @return [ParserNamespace]
    def parser
      @parser_namespace ||= ParserNamespace.new(@terminal.parser)
    end

    # Returns unicode configuration and provider registration APIs.
    # @return [UnicodeNamespace]
    def unicode
      @unicode_namespace ||= UnicodeNamespace.new(@terminal.unicode_handler)
    end

    # Returns the current terminal modes.
    # @return [Hash<Symbol, Boolean>]
    def modes
      @terminal.input_handler.modes
    end

    # Returns the current terminal options.
    # @return [TerminalOptions]
    def options
      @terminal.options
    end

    # @return [String] current window title from OSC 0/2
    def title
      @terminal.input_handler.title
    end

    # @return [String] current icon name from OSC 0/1
    def icon_name
      @terminal.input_handler.icon_name
    end

    # --- Buffer Operations ---

    # Clears the terminal buffer.
    def clear
      @terminal.clear
    end

    # Resets the terminal to its initial state.
    def reset
      @terminal.reset
    end

    # Scrolls the viewport by the given number of lines.
    # @param amount [Integer]
    def scroll_lines(amount)
      @terminal.scroll_lines(amount)
    end

    # Scrolls to the top of the scrollback.
    def scroll_to_top
      @terminal.scroll_to_top
    end

    # Scrolls to the bottom.
    def scroll_to_bottom
      @terminal.scroll_to_bottom
    end

    # Selects text from the active buffer.
    # @param column [Integer] start column
    # @param row [Integer] start row
    # @param length [Integer] number of characters to select
    def select(column, row, length)
      @selection = {
        type: :linear,
        column: [column.to_i, 0].max,
        row: [row.to_i, 0].max,
        length: [length.to_i, 0].max
      }
    end

    # Selects the word at the given visible buffer position.
    # @param column [Integer] cell column
    # @param row [Integer] visible row
    def select_word(column, row)
      @selection = {
        type: :word,
        column: [column.to_i, 0].max,
        row: [row.to_i, 0].max
      }
    end

    # Selects a rectangular cell range in the visible buffer.
    # @param start_column [Integer] starting column
    # @param start_row [Integer] starting row
    # @param end_column [Integer] ending column, inclusive
    # @param end_row [Integer] ending row, inclusive
    def select_rectangle(start_column, start_row, end_column, end_row)
      @selection = {
        type: :rectangle,
        start_column: [start_column.to_i, 0].max,
        start_row: [start_row.to_i, 0].max,
        end_column: [end_column.to_i, 0].max,
        end_row: [end_row.to_i, 0].max
      }
    end

    # Selects all retained text in the active buffer, including scrollback.
    def select_all
      @selection = {
        type: :all
      }
    end

    # @return [String] selected text
    def selection
      return "" unless @selection

      case @selection[:type]
      when :linear
        return "" unless @selection[:length].positive?

        selected_buffer_text(@selection[:column], @selection[:row], @selection[:length])
      when :word
        selected_word_text(@selection[:column], @selection[:row])
      when :rectangle
        selected_rectangle_text(@selection)
      when :all
        selected_all_text
      else
        ""
      end
    end

    # Clears the current text selection.
    def clear_selection
      @selection = nil
    end

    # --- Resize ---

    # Resizes the terminal.
    # @param cols [Integer] new number of columns
    # @param rows [Integer] new number of rows
    def resize(cols, rows)
      @terminal.resize(cols, rows)
    end

    # Encodes a mouse event according to the active DEC mouse mode.
    # @return [String, nil]
    def mouse_event(**options)
      @terminal.input_handler.mouse_report(**options)
    end

    # Encodes a focus event according to DEC focus reporting mode.
    # @param focused [Boolean]
    # @return [String, nil]
    def focus_event(focused: true)
      @terminal.input_handler.focus_report(focused)
    end

    # --- Events ---

    # Registers an event listener.
    # @param event [Symbol] the event name
    # @yield the callback block
    # @return [Common::Disposable]
    def on(event, &block)
      @terminal.on(event, &block)
    end

    # --- Addons ---

    # Loads an addon into the terminal.
    # @param addon [Addon::Base] the addon to load
    def load_addon(addon)
      addon.activate(self)
      @addons << addon
    end

    # Disposes of the terminal and all loaded addons.
    def dispose
      @addons.each(&:dispose)
      @addons.clear
      @terminal.dispose
    end

    # Provides access to internal terminal for addons.
    # @return [Headless::HeadlessTerminal]
    # @api private
    def internal
      @terminal
    end

    private

    def visible_rows
      active = buffer.active
      collect_rows(active.y_disp, active.rows)
    end

    def all_rows
      collect_rows(0, buffer.active.lines.length)
    end

    def collect_rows(start_index, count)
      active = buffer.active
      last_index = [start_index + count, active.lines.length].min
      rows = (start_index...last_index).filter_map do |index|
        line = active.lines[index]
        next unless line

        { line: line, wrapped_to_next: line.is_wrapped }
      end

      rows.pop while rows.last && line_empty?(rows.last[:line])
      rows
    end

    def line_empty?(line)
      line.get_trimmed_length.zero?
    end

    def selected_all_text
      join_row_text(all_rows)
    end

    def selected_buffer_text(column, row, length)
      rows = visible_rows
      current_row = [[row, 0].max, rows.length].min
      current_col = [column, 0].max
      remaining = length
      result = +""
      first_line = true
      previous_wrapped = false

      while remaining.positive? && current_row < rows.length
        row_info = rows[current_row]
        line = row_info[:line]
        result << "\r\n" unless first_line || previous_wrapped
        first_line = false

        available = [line.get_trimmed_length - current_col, 0].max
        take = [available, remaining].min
        result << line_text(line, start_col: current_col, end_col: current_col + take)
        remaining -= take
        previous_wrapped = row_info[:wrapped_to_next]
        current_row += 1
        current_col = 0
      end

      result
    end

    def selected_word_text(column, row)
      row_info = visible_rows[[row, 0].max]
      return "" unless row_info

      segments = line_segments(row_info[:line])
      target = segments.find_index { |segment| column >= segment[:start_col] && column < segment[:end_col] }
      target ||= segments.length - 1 if segments.any? && column >= segments.last[:end_col]
      return "" unless target

      separators = options.word_separator.to_s.each_char.to_a
      return "" if separators.include?(segments[target][:text])

      first = target
      first -= 1 while first.positive? && !separators.include?(segments[first - 1][:text])

      last = target
      last += 1 while last < segments.length - 1 && !separators.include?(segments[last + 1][:text])

      segments[first..last].map { |segment| segment[:text] }.join
    end

    def selected_rectangle_text(selection)
      rows = visible_rows
      first_row, last_row = [selection[:start_row], selection[:end_row]].minmax
      first_col, last_col = [selection[:start_column], selection[:end_column]].minmax

      (first_row..last_row).map do |row_index|
        row_info = rows[row_index]
        row_info ? line_text(row_info[:line], start_col: first_col, end_col: last_col + 1, trim_right: false) : ""
      end.join("\r\n")
    end

    def join_row_text(rows)
      result = +""
      rows.each_with_index do |row_info, index|
        result << "\r\n" if index.positive? && !rows[index - 1][:wrapped_to_next]
        result << line_text(row_info[:line])
      end
      result
    end

    def line_text(line, start_col: 0, end_col: nil, trim_right: true)
      line_segments(line, start_col: start_col, end_col: end_col, trim_right: trim_right)
        .map { |segment| segment[:text] }
        .join
    end

    def line_segments(line, start_col: 0, end_col: nil, trim_right: true)
      start_col = [start_col, 0].max
      max_end = trim_right ? line.get_trimmed_length : line.length
      end_col = end_col ? [end_col, max_end].min : max_end
      return [] if end_col <= start_col

      segments = []
      column = 0
      while column < end_col
        cell = line.get_cell(column)
        width = [(cell&.width || 1).to_i, 1].max
        next_column = column + width

        if cell && cell.width != 0 && next_column > start_col
          segments << {
            text: cell.has_content? ? cell.char : " ",
            start_col: column,
            end_col: next_column
          }
        end

        column = next_column
      end
      segments
    end
  end

  # Provides access to active/normal/alt buffers with a clean API.
  class BufferNamespace
    # @return [Common::Buffer] the currently active buffer
    def active
      @buffer_set.active
    end

    # @return [Common::Buffer] the normal buffer
    def normal
      @buffer_set.normal
    end

    # @return [Common::Buffer] the alternate buffer
    def alt
      @buffer_set.alt
    end

    private

    def initialize(buffer_set)
      @buffer_set = buffer_set
    end
  end

  class ParserNamespace
    def initialize(parser)
      @parser = parser
    end

    def register_csi_handler(id, &block)
      @parser.set_csi_handler(id, &block)
    end

    def set_print_handler(&block)
      @parser.set_print_handler(&block)
    end

    def set_execute_handler(code, &block)
      @parser.set_execute_handler(code, &block)
    end

    def register_esc_handler(id, &block)
      @parser.set_esc_handler(id, &block)
    end

    def register_osc_handler(id, &block)
      @parser.set_osc_handler(id, &block)
    end

    def register_dcs_handler(id, &block)
      @parser.set_dcs_handler(id, &block)
    end

    alias set_csi_handler register_csi_handler
    alias set_esc_handler register_esc_handler
    alias set_osc_handler register_osc_handler
    alias set_dcs_handler register_dcs_handler
  end

  class UnicodeNamespace
    def initialize(unicode_handler)
      @unicode_handler = unicode_handler
    end

    def active_version
      @unicode_handler.active_version
    end

    def active_version=(version)
      @unicode_handler.active_version = version
    end

    def versions
      @unicode_handler.versions
    end

    def register(version, provider)
      @unicode_handler.register(version, provider)
    end
  end
end
