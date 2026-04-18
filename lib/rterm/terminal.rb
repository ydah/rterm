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
        column: [column.to_i, 0].max,
        row: [row.to_i, 0].max,
        length: [length.to_i, 0].max
      }
    end

    # Selects all visible text in the active buffer.
    def select_all
      lines = visible_text_lines
      @selection = {
        column: 0,
        row: 0,
        length: lines.sum(&:length)
      }
    end

    # @return [String] selected text
    def selection
      return "" unless @selection && @selection[:length].positive?

      selected_buffer_text(@selection[:column], @selection[:row], @selection[:length])
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

    def visible_selection_text
      visible_text_lines.join("\r\n")
    end

    def visible_text_lines
      active = buffer.active
      lines = active.rows.times.map do |row|
        active.get_line(row)&.to_string || ""
      end
      lines.pop while lines.last == ""
      lines
    end

    def selected_buffer_text(column, row, length)
      lines = visible_text_lines
      current_row = [[row, 0].max, lines.length].min
      current_col = [column, 0].max
      remaining = length
      result = +""
      first_line = true

      while remaining.positive? && current_row < lines.length
        line = lines[current_row]
        result << "\r\n" unless first_line
        first_line = false

        available = [line.length - current_col, 0].max
        take = [available, remaining].min
        result << (line[current_col, take] || "")
        remaining -= take
        current_row += 1
        current_col = 0
      end

      result
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
