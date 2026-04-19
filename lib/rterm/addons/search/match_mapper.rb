# frozen_string_literal: true

module RTerm
  module Addon
    class Search < Base
      class MatchMapper
        def self.build(logical_line, offset, text)
          position = position_for_offset(logical_line[:segments], offset)
          ranges = ranges_for_offsets(logical_line[:segments], offset, text.length)
          return nil unless position && ranges.any?

          {
            row: position[:row],
            line_index: position[:line_index],
            col: position[:col],
            length: ranges.sum { |range| range[:length] },
            text: text,
            ranges: ranges
          }
        end

        def self.position_for_offset(segments, offset)
          segment = segments.find { |item| offset >= item[:start] && offset < item[:end] }
          segment ||= segments.last if segments.any? && offset >= segments.last[:end]
          return nil unless segment

          { row: segment[:row], line_index: segment[:line_index], col: segment[:col] }
        end

        def self.ranges_for_offsets(segments, start, length)
          finish = start + length
          ranges = []

          segments.each do |segment|
            next if segment[:end] <= start || segment[:start] >= finish

            append_range(ranges, segment)
          end

          ranges
        end

        def self.append_range(ranges, segment)
          last = ranges.last
          if last && last[:row] == segment[:row] && last[:col] + last[:length] == segment[:col]
            last[:length] += segment[:width]
          else
            ranges << {
              row: segment[:row],
              line_index: segment[:line_index],
              col: segment[:col],
              length: segment[:width]
            }
          end
        end
      end
    end
  end
end
