# frozen_string_literal: true

require_relative "buffer_line"
require_relative "circular_list"

module RTerm
  module Common
    # Terminal buffer that manages lines of cell data with scrollback support.
    # Uses CircularList for efficient line storage.
    class Buffer
      attr_reader :cols, :rows, :lines, :scrollback, :tabs
      attr_accessor :x, :y, :y_base, :y_disp, :scroll_top, :scroll_bottom
      attr_accessor :saved_x, :saved_y, :saved_cur_attr

      # @param cols [Integer] number of columns
      # @param rows [Integer] number of rows
      # @param scrollback [Integer] number of scrollback lines
      def initialize(cols, rows, scrollback = 1000)
        @cols = cols
        @rows = rows
        @scrollback = scrollback
        @x = 0
        @y = 0
        @y_base = 0
        @y_disp = 0
        @scroll_top = 0
        @scroll_bottom = rows - 1
        @saved_x = 0
        @saved_y = 0
        @saved_cur_attr = nil
        @tabs = {}
        @lines = CircularList.new(rows + scrollback)

        setup_tab_stops
        fill_viewport
      end

      # Returns the BufferLine at the given viewport row.
      # @param y [Integer] the viewport row (0-based)
      # @return [BufferLine, nil]
      def get_line(y)
        @lines[@y_base + y]
      end

      # Scrolls the buffer up by the given number of lines.
      # @param count [Integer] lines to scroll
      def scroll_up(count = 1)
        count.times do
          @lines.push(new_blank_line)
          @y_base += 1
          @y_disp = @y_base
        end
      end

      # Scrolls content down within the scroll region.
      # @param count [Integer] lines to scroll
      def scroll_down(count = 1)
        count.times do
          # Remove bottom line in scroll region and insert blank at top
          top = @scroll_top + @y_base
          bottom = @scroll_bottom + @y_base

          # Shift lines down within the scroll region
          (bottom).downto(top + 1) do |i|
            src = @lines[i - 1]
            if src
              @lines[i] = src.clone
            end
          end

          @lines[top] = new_blank_line
        end
      end

      # Resizes the buffer to the given dimensions.
      # @param new_cols [Integer] new number of columns
      # @param new_rows [Integer] new number of rows
      def resize(new_cols, new_rows)
        fill = CellData.new

        # Resize existing lines
        @lines.each do |line|
          line.resize(new_cols, fill) if line
        end

        # Add or remove rows
        if new_rows > @rows
          (new_rows - @rows).times do
            @lines.push(BufferLine.new(new_cols))
          end
        end

        @cols = new_cols
        @rows = new_rows
        @scroll_bottom = new_rows - 1 if @scroll_bottom >= new_rows
        @lines.max_length = new_rows + @scrollback
        @x = [@x, new_cols - 1].min
        @y = [@y, new_rows - 1].min
      end

      # Saves the current cursor position and optional attributes.
      def save_cursor(cur_attr = nil)
        @saved_x = @x
        @saved_y = @y
        @saved_cur_attr = cur_attr&.clone
      end

      # Restores the previously saved cursor position and returns saved attributes.
      def restore_cursor
        @x = [@saved_x, @cols - 1].min
        @y = [@saved_y, @rows - 1].min
        @saved_cur_attr&.clone
      end

      # Clears all lines in the buffer.
      def clear
        @lines.length.times do |i|
          @lines[i] = new_blank_line
        end
        @y_base = 0
        @y_disp = 0
        @x = 0
        @y = 0
        @saved_x = 0
        @saved_y = 0
        @saved_cur_attr = nil
      end

      private

      def new_blank_line
        BufferLine.new(@cols)
      end

      def fill_viewport
        @rows.times do
          @lines.push(new_blank_line)
        end
      end

      def setup_tab_stops
        @cols.times { |i| @tabs[i] = true if i > 0 && (i % 8) == 0 }
      end
    end
  end
end
