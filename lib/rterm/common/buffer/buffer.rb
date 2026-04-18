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
          @y_base = [@y_base + 1, max_y_base].min
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
        old_scroll_bottom = @scroll_bottom
        old_rows = @rows
        reflow_lines(new_cols, new_rows) if new_cols != @cols

        @cols = new_cols
        @rows = new_rows
        @lines.max_length = new_rows + @scrollback
        @lines.push(new_blank_line) while @lines.length < new_rows
        @scroll_bottom = if old_scroll_bottom == old_rows - 1 || @scroll_bottom >= new_rows
                           new_rows - 1
                         else
                           @scroll_bottom
                         end
        @y_base = [@y_base, max_y_base].min
        @y_disp = [@y_disp, @y_base].min
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
        @lines.clear
        fill_viewport
        @y_base = 0
        @y_disp = 0
        @x = 0
        @y = 0
        @saved_x = 0
        @saved_y = 0
        @saved_cur_attr = nil
      end

      # Returns the visible wrapped range containing a row.
      # @param y [Integer]
      # @return [Range]
      def get_wrapped_range_for_line(y)
        first = y
        first -= 1 while first.positive? && get_line(first - 1)&.is_wrapped

        last = y
        last += 1 while last < @rows - 1 && get_line(last)&.is_wrapped

        first..last
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

      def max_y_base
        [@lines.length - @rows, 0].max
      end

      def reflow_lines(new_cols, new_rows)
        groups = logical_line_groups
        reflowed = groups.flat_map { |group| reflow_group(group, new_cols) }
        reflowed << BufferLine.new(new_cols) while reflowed.length < new_rows

        @lines = CircularList.new(new_rows + @scrollback)
        reflowed.each { |line| @lines.push(line) }
      end

      def logical_line_groups
        groups = []
        current = []

        @lines.each do |line|
          next unless line

          current << line
          next if line.is_wrapped

          groups << current
          current = []
        end

        groups << current unless current.empty?
        groups
      end

      def reflow_group(group, new_cols)
        cells = group.flat_map { |line| reflowable_cells(line) }
        return [BufferLine.new(new_cols)] if cells.empty?

        lines = []
        current_line = BufferLine.new(new_cols)
        current_col = 0

        cells.each do |cell|
          width = [cell.width, 1].max
          if current_col.positive? && current_col + width > new_cols
            current_line.is_wrapped = true
            lines << current_line
            current_line = BufferLine.new(new_cols)
            current_col = 0
          end

          current_line.set_cell(current_col, cell)
          if width == 2 && current_col + 1 < new_cols
            spacer = CellData.new
            spacer.width = 0
            current_line.set_cell(current_col + 1, spacer)
          end
          current_col += width
        end

        lines << current_line
        lines
      end

      def reflowable_cells(line)
        trimmed = line.get_trimmed_length
        cells = []
        trimmed.times do |index|
          cell = line.get_cell(index)
          next unless cell
          next if cell.width.zero?

          cells << cell.clone
        end
        cells
      end
    end
  end
end
