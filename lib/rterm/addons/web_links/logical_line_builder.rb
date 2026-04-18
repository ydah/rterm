# frozen_string_literal: true

module RTerm
  module Addon
    class WebLinks < Base
      class LogicalLineBuilder
        def initialize(buffer)
          @buffer = buffer
        end

        def call(row: nil)
          groups = build_groups
          return groups unless row

          row = row.to_i
          groups.select { |group| row >= group[:start_row] && row <= group[:end_row] }
        end

        private

        def build_groups
          groups = []
          current = nil

          visible_rows.each do |row_info|
            current ||= { text: +"", segments: [], start_row: row_info[:row], end_row: row_info[:row] }
            append_line_text(current, row_info)
            current[:end_row] = row_info[:row]

            next if row_info[:wrapped_to_next]

            groups << current
            current = nil
          end
          groups << current if current
          groups
        end

        def visible_rows
          start_index = @buffer.y_disp
          last_index = [start_index + @buffer.rows, @buffer.lines.length].min
          (start_index...last_index).filter_map do |index|
            line = @buffer.lines[index]
            next unless line

            {
              row: index - start_index,
              line: line,
              wrapped_to_next: line.is_wrapped
            }
          end
        end

        def append_line_text(group, row_info)
          trim_right = !row_info[:wrapped_to_next]
          max_col = trim_right ? row_info[:line].get_trimmed_length : row_info[:line].length
          col = 0

          while col < max_col
            cell = row_info[:line].get_cell(col)
            width = [(cell&.width || 1).to_i, 1].max
            next_col = col + width

            append_cell_text(group, row_info, cell, col, width) if cell && cell.width != 0
            col = next_col
          end
        end

        def append_cell_text(group, row_info, cell, col, width)
          text = cell.has_content? ? cell.char : " "
          start = group[:text].length
          group[:text] << text
          group[:segments] << {
            start: start,
            end: group[:text].length,
            row: row_info[:row],
            col: col,
            width: width
          }
        end
      end
    end
  end
end
