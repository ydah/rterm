# frozen_string_literal: true

require_relative "../base"

module RTerm
  module Addon
    class Search < Base
      def activate(terminal)
        super
        @current_match = nil
        @current_match_index = nil
      end

      # Find next occurrence of term
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive
      # @return [Hash, nil] {row:, col:, length:} or nil
      def find_next(term, options = {})
        all = find_all(term, options)
        return nil if all.empty?

        if @current_match.nil?
          @current_match_index = 0
        else
          @current_match_index = ((@current_match_index || 0) + 1) % all.length
        end

        @current_match = all[@current_match_index]
      end

      # Find previous occurrence
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive
      # @return [Hash, nil] {row:, col:, length:} or nil
      def find_previous(term, options = {})
        all = find_all(term, options)
        return nil if all.empty?

        if @current_match.nil?
          @current_match_index = all.length - 1
        else
          @current_match_index = ((@current_match_index || 0) - 1) % all.length
        end

        @current_match = all[@current_match_index]
      end

      # Find all occurrences
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive
      # @return [Array<Hash>] array of {row:, col:, length:}
      def find_all(term, options = {})
        return [] if term.nil? || term.empty?

        matches = []
        buffer = @terminal.internal.buffer_set.active
        regex = build_regex(term, options)

        logical_lines(buffer).each do |logical_line|
          text = logical_line[:text]
          text.scan(regex) do
            m = Regexp.last_match
            position = buffer_position_for(logical_line[:segments], m.begin(0))
            matches << { row: position[:row], col: position[:col], length: m[0].length }
          end
        end

        matches
      end

      def clear_decorations
        @current_match = nil
        @current_match_index = nil
      end

      def dispose
        clear_decorations
        super
      end

      private

      def build_regex(term, options)
        pattern = if options[:regex]
                    term
                  else
                    Regexp.escape(term)
                  end

        pattern = "\\b#{pattern}\\b" if options[:whole_word]

        flags = options[:case_sensitive] ? 0 : Regexp::IGNORECASE
        Regexp.new(pattern, flags)
      end

      def logical_lines(buffer)
        lines = []
        current = nil

        buffer.rows.times do |row|
          line = buffer.get_line(row)
          next unless line

          text = line.to_string(trim_right: false)
          current ||= { text: +"", segments: [] }
          current[:segments] << { row: row, start: current[:text].length, length: text.length }
          current[:text] << text

          next if line.is_wrapped

          lines << current
          current = nil
        end

        lines << current if current
        lines
      end

      def buffer_position_for(segments, offset)
        segment = segments.find { |item| offset < item[:start] + item[:length] } || segments.last
        {
          row: segment[:row],
          col: offset - segment[:start]
        }
      end
    end
  end
end
