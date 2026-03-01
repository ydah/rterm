# frozen_string_literal: true

require_relative "../base"

module RTerm
  module Addon
    class WebLinks < Base
      URL_REGEX = %r{https?://[^\s<>\[\]{}|\\^`"]+}i

      # Find all URLs in the buffer
      # @return [Array<Hash>] array of {url:, row:, col:, length:}
      def find_links
        links = []
        buffer = @terminal.internal.buffer_set.active
        buffer.rows.times do |y|
          line = buffer.get_line(y)
          next unless line

          text = line.to_string(trim_right: false)
          text.scan(URL_REGEX) do
            match = Regexp.last_match
            links << { url: match[0], row: y, col: match.begin(0), length: match[0].length }
          end
        end
        links
      end
    end
  end
end
