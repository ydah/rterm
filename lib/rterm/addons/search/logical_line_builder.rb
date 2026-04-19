# frozen_string_literal: true

module RTerm
  module Addon
    class Search < Base
      class LogicalLineBuilder
        def initialize(buffer)
          @buffer = buffer
        end

        def call(options = {})
          start_index, finish_index = line_bounds(options)
          lines = []
          current = nil

          (start_index..finish_index).each do |line_index|
            line = @buffer.lines[line_index]
            next unless line

            current ||= { text: +"", segments: [], start_line_index: line_index }
            append_line_segments(current, line, line_index - start_index, line_index, trim_right: !line.is_wrapped)

            next if line.is_wrapped

            lines << current
            current = nil
          end

          lines << current if current
          lines
        end

        private

        def line_bounds(options)
          if options[:include_scrollback] || options[:scrollback] == true || options[:scrollback] == :all
            return [0, @buffer.lines.length - 1]
          end

          scrollback = [options[:scrollback].to_i, 0].max
          start = scrollback.positive? ? [@buffer.y_base - scrollback, 0].max : @buffer.y_disp
          finish = [@buffer.y_base + @buffer.rows - 1, @buffer.lines.length - 1].min
          [start, finish]
        end

        def append_line_segments(current, line, row, line_index, trim_right:)
          max_col = trim_right ? line.get_trimmed_length : line.length
          col = 0

          while col < max_col
            cell = line.get_cell(col)
            width = [(cell&.width || 1).to_i, 1].max
            next_col = col + width

            append_cell_segment(current, cell, row, line_index, col, width) if cell && cell.width != 0
            col = next_col
          end
        end

        def append_cell_segment(current, cell, row, line_index, col, width)
          text = cell.has_content? ? cell.char : " "
          start = current[:text].length
          current[:text] << text
          current[:segments] << {
            row: row,
            line_index: line_index,
            col: col,
            width: width,
            start: start,
            end: current[:text].length
          }
        end
      end
    end
  end
end
