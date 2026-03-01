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
      @terminal.emit(:data, data)
    end

    # --- Buffer Access ---

    # Returns the buffer namespace for accessing buffer content.
    # @return [BufferNamespace]
    def buffer
      @buffer_namespace ||= BufferNamespace.new(@terminal.buffer_set)
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

    # --- Resize ---

    # Resizes the terminal.
    # @param cols [Integer] new number of columns
    # @param rows [Integer] new number of rows
    def resize(cols, rows)
      @terminal.resize(cols, rows)
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
end
