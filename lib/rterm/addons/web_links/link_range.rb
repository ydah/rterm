# frozen_string_literal: true

module RTerm
  module Addon
    class WebLinks < Base
      class LinkRange
        def self.position_for(segments, offset)
          segment = segments.find { |candidate| offset >= candidate[:start] && offset < candidate[:end] }
          segment ||= segments.last if segments.any? && offset >= segments.last[:end]
          return nil unless segment

          { row: segment[:row], col: segment[:col] }
        end

        def self.ranges_for(segments, start, length)
          finish = start + length
          ranges = []

          segments.each do |segment|
            next if segment[:end] <= start || segment[:start] >= finish

            last = ranges.last
            if last && last[:row] == segment[:row] && last[:col] + last[:length] == segment[:col]
              last[:length] += segment[:width]
            else
              ranges << { row: segment[:row], col: segment[:col], length: segment[:width] }
            end
          end

          ranges
        end
      end
    end
  end
end
