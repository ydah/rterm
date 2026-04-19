# frozen_string_literal: true

require_relative "../base"
require_relative "logical_line_builder"
require_relative "match_mapper"

module RTerm
  module Addon
    class Search < Base
      attr_reader :decorations

      def activate(terminal)
        super
        @current_match = nil
        @current_match_index = nil
        @current_query_key = nil
        @decorations = []
      end

      # Find next occurrence of term
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive
      # @return [Hash, nil] {row:, col:, length:} or nil
      def find_next(term, options = {})
        all = find_all(term, options)
        return nil if all.empty?

        query_key = query_key(term, options)
        if @current_match.nil? || @current_query_key != query_key
          @current_match_index = 0
        else
          @current_match_index = ((@current_match_index || 0) + 1) % all.length
        end

        @current_query_key = query_key
        @current_match = all[@current_match_index]
      end

      # Find previous occurrence
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive
      # @return [Hash, nil] {row:, col:, length:} or nil
      def find_previous(term, options = {})
        all = find_all(term, options)
        return nil if all.empty?

        query_key = query_key(term, options)
        if @current_match.nil? || @current_query_key != query_key
          @current_match_index = all.length - 1
        else
          @current_match_index = ((@current_match_index || 0) - 1) % all.length
        end

        @current_query_key = query_key
        @current_match = all[@current_match_index]
      end

      # Find all occurrences
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive, :scrollback, :decorations
      # @return [Array<Hash>] array of {row:, col:, length:}
      def find_all(term, options = {})
        return [] if term.nil? || term.empty?

        matches = []
        buffer = @terminal.internal.buffer_set.active
        regex = build_regex(term, options)

        logical_lines(buffer, options).each do |logical_line|
          text = logical_line[:text]
          text.scan(regex) do
            m = Regexp.last_match
            match = MatchMapper.build(logical_line, m.begin(0), m[0])
            matches << match if match
          end
        end

        @decorations = decorate(matches, options[:decorations]) if options[:decorations]
        matches
      rescue RegexpError
        []
      end

      def clear_decorations
        @current_match = nil
        @current_match_index = nil
        @current_query_key = nil
        @decorations = []
      end

      def dispose
        clear_decorations
        super
      end

      private

      def query_key(term, options)
        [
          term,
          options[:regex] == true,
          options[:whole_word] == true,
          options[:case_sensitive] == true,
          options[:scrollback],
          options[:include_scrollback]
        ]
      end

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

      def logical_lines(buffer, options = {})
        LogicalLineBuilder.new(buffer).call(options)
      end

      def decorate(matches, style)
        matches.map { |match| match.merge(decoration: style) }
      end
    end
  end
end
