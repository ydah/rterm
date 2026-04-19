# frozen_string_literal: true

require_relative "cell_data"

module RTerm
  module Common
    # Represents a single line in the terminal buffer.
    # Manages an array of CellData objects for each column.
    class BufferLine
      attr_accessor :is_wrapped

      # @param cols [Integer] the number of columns
      # @param fill_cell [CellData, nil] the cell to fill with
      def initialize(cols, fill_cell = nil)
        @cells = Array.new(cols) do
          if fill_cell
            fill_cell.clone
          else
            CellData.new
          end
        end
        @is_wrapped = false
      end

      # @return [Integer] the number of columns
      def length
        @cells.length
      end

      # Returns the cell at the given column.
      # @param x [Integer] the column index
      # @return [CellData]
      def get_cell(x)
        @cells[x]
      end

      # Sets the cell at the given column.
      # @param x [Integer] the column index
      # @param cell [CellData] the cell data to set
      def set_cell(x, cell)
        return if x < 0 || x >= @cells.length

        if cell.width.zero?
          @cells[x].copy_from(cell)
          return
        end

        fill = CellData.new
        if cell.width == 2 && x == @cells.length - 1
          clear_wide_cell_at(x, fill)
          @cells[x].copy_from(fill)
          return
        end

        clear_wide_cell_at(x, fill)
        clear_wide_cell_at(x + 1, fill) if cell.width == 2

        @cells[x].copy_from(cell)
        set_spacer_cell(x + 1, cell) if cell.width == 2
      end

      # Inserts blank cells at the given position, shifting existing cells right.
      # Cells that fall off the end are discarded.
      # @param x [Integer] the insertion position
      # @param count [Integer] the number of cells to insert
      # @param fill [CellData] the fill cell for inserted positions
      def insert_cells(x, count, fill)
        return if x < 0 || x >= @cells.length

        count = [count, @cells.length - x].min
        clear_split_wide_char_at_insert(x, fill)

        # Shift cells right
        (@cells.length - 1).downto(x + count) do |i|
          @cells[i].copy_from(@cells[i - count])
        end

        # Fill inserted positions
        count.times do |i|
          @cells[x + i].copy_from(fill)
        end
        normalize_wide_cells(fill)
      end

      # Deletes cells at the given position, shifting remaining cells left.
      # Vacated positions on the right are filled.
      # @param x [Integer] the deletion position
      # @param count [Integer] the number of cells to delete
      # @param fill [CellData] the fill cell for vacated positions
      def delete_cells(x, count, fill)
        return if x < 0 || x >= @cells.length

        count = [count, @cells.length - x].min
        clear_split_wide_chars_in_delete_range(x, x + count, fill)

        # Shift cells left
        (x...(@cells.length - count)).each do |i|
          @cells[i].copy_from(@cells[i + count])
        end

        # Fill vacated positions
        ((@cells.length - count)...@cells.length).each do |i|
          @cells[i].copy_from(fill)
        end
        normalize_wide_cells(fill)
      end

      # Replaces cells in the given range with the fill cell.
      # @param start_col [Integer] the start column (inclusive)
      # @param end_col [Integer] the end column (exclusive)
      # @param fill [CellData] the fill cell
      def replace_cells(start_col, end_col, fill)
        start_col = [[start_col, 0].max, @cells.length].min
        end_col = [end_col, @cells.length].min
        end_col = [end_col, 0].max
        return if start_col >= end_col

        start_col -= 1 if start_col.positive? && right_half_of_wide_char?(start_col)
        end_col += 1 if end_col < @cells.length && end_col.positive? && @cells[end_col - 1].width == 2

        (start_col...end_col).each do |i|
          @cells[i].copy_from(fill)
        end
      end

      # Resizes the line to the given number of columns.
      # @param cols [Integer] the new number of columns
      # @param fill [CellData] the fill cell for new positions
      def resize(cols, fill)
        if cols > @cells.length
          (cols - @cells.length).times do
            @cells << (fill ? fill.clone : CellData.new)
          end
        elsif cols < @cells.length
          @cells = @cells[0, cols]
          normalize_wide_cells(fill || CellData.new)
        end
      end

      # Returns the text content of the line as a string.
      # @param trim_right [Boolean] whether to trim trailing empty cells
      # @param start_col [Integer] the start column
      # @param end_col [Integer, nil] the end column (exclusive), nil for end of line
      # @return [String]
      def to_string(trim_right: true, start_col: 0, end_col: nil)
        end_col ||= @cells.length
        end_col = [end_col, @cells.length].min

        if trim_right
          trimmed = get_trimmed_length
          end_col = trimmed if end_col > trimmed
        end

        result = +""
        (start_col...end_col).each do |i|
          cell = @cells[i]
          next if cell.width == 0 # skip trailing part of wide char

          if cell.has_content?
            result << cell.char
          else
            result << " "
          end
        end
        result
      end

      # Returns the length of the line excluding trailing empty/space cells.
      # @return [Integer]
      def get_trimmed_length
        i = @cells.length - 1
        while i >= 0
          cell = @cells[i]
          if cell.has_content? && cell.char != " "
            return i + 1
          end
          i -= 1
        end
        0
      end

      # Creates a deep copy of this line.
      # @return [BufferLine]
      def clone
        new_line = BufferLine.allocate
        new_line.instance_variable_set(:@cells, @cells.map(&:clone))
        new_line.instance_variable_set(:@is_wrapped, @is_wrapped)
        new_line
      end

      private

      def set_spacer_cell(x, source)
        return if x >= @cells.length

        spacer = source.clone
        spacer.char = ""
        spacer.width = 0
        @cells[x].copy_from(spacer)
      end

      def clear_wide_cell_at(x, fill)
        return if x < 0 || x >= @cells.length

        if right_half_of_wide_char?(x)
          @cells[x - 1].copy_from(fill)
          @cells[x].copy_from(fill)
        elsif @cells[x].width == 2 && x + 1 < @cells.length
          @cells[x + 1].copy_from(fill)
        end
      end

      def clear_split_wide_char_at_insert(x, fill)
        return unless right_half_of_wide_char?(x)

        @cells[x - 1].copy_from(fill)
        @cells[x].copy_from(fill)
      end

      def clear_split_wide_chars_in_delete_range(start_col, end_col, fill)
        (0...(@cells.length - 1)).each do |i|
          next unless @cells[i].width == 2

          span_start = i
          span_end = i + 2
          intersects = span_start < end_col && start_col < span_end
          fully_deleted = start_col <= span_start && span_end <= end_col
          next unless intersects && !fully_deleted

          @cells[i].copy_from(fill)
          @cells[i + 1].copy_from(fill)
        end
      end

      def normalize_wide_cells(fill)
        i = 0
        while i < @cells.length
          cell = @cells[i]
          if cell.width.zero?
            @cells[i].copy_from(fill) unless right_half_of_wide_char?(i)
            i += 1
          elsif cell.width == 2
            if i + 1 >= @cells.length || @cells[i + 1].width != 0
              @cells[i].copy_from(fill)
              i += 1
            else
              i += 2
            end
          else
            i += 1
          end
        end
      end

      def right_half_of_wide_char?(x)
        x.positive? && @cells[x].width.zero? && @cells[x - 1].width == 2
      end
    end
  end
end
