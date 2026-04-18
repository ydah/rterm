# frozen_string_literal: true

require_relative "../common/core_terminal"

module RTerm
  module Headless
    # Headless terminal implementation — provides full terminal emulation
    # without any rendering dependency. Suitable for server-side use,
    # testing, and integration with WebSocket bridges.
    class HeadlessTerminal < Common::CoreTerminal
      # @param options [Hash] terminal options
      # @option options [Integer] :cols (80) number of columns
      # @option options [Integer] :rows (24) number of rows
      # @option options [Integer] :scrollback (1000) scrollback buffer size
      def initialize(options = {})
        super(options)
      end

      # Returns the active buffer.
      # @return [Common::Buffer]
      def buffer
        @buffer_set.active
      end

      # Returns a specific line from the active buffer.
      # @param y [Integer] the row index (0-based, viewport-relative)
      # @return [Common::BufferLine, nil]
      def get_line(y)
        buffer.get_line(y)
      end

      # Scrolls the viewport by the given number of lines.
      # @param amount [Integer] positive = down, negative = up
      def scroll_lines(amount)
        max_disp = buffer.y_base
        buffer.y_disp = [[buffer.y_disp + amount, 0].max, max_disp].min
        emit(:scroll)
      end

      # Scrolls to the top of the scrollback buffer.
      def scroll_to_top
        buffer.y_disp = 0
        emit(:scroll)
      end

      # Scrolls to the bottom (most recent content).
      def scroll_to_bottom
        buffer.y_disp = buffer.y_base
        emit(:scroll)
      end

      # Clears the terminal buffer.
      def clear
        buffer.clear
      end

      # Disposes of the terminal and releases resources.
      def dispose
        remove_all_listeners
      end
    end
  end
end
