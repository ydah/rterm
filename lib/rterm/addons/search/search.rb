# frozen_string_literal: true

require_relative "../base"
require_relative "logical_line_builder"
require_relative "match_mapper"

module RTerm
  module Addon
    class Search < Base
      attr_reader :decorations, :matches

      def activate(terminal)
        super
        @current_match = nil
        @current_match_index = nil
        @current_query_key = nil
        @decorations = []
        @matches = []
        @last_term = nil
        @last_options = {}
        @last_error = nil
      end

      # Returns the last search state for incremental UIs.
      # @return [Hash]
      def state
        {
          query: @last_term,
          options: deep_dup(@last_options),
          matches: deep_dup(@matches),
          current_index: @current_match_index,
          current_match: deep_dup(@current_match),
          decorations: deep_dup(@decorations),
          error: @last_error
        }
      end

      # Updates the incremental search state without moving the current match.
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive, :scrollback, :decorations
      # @return [Hash] current search state
      def update(term, options = {})
        find_all(term, options)
        state
      end

      # Restores search state produced by #state.
      # @param data [Hash]
      # @param emit [Boolean] whether to emit a decoration update event
      # @return [Hash]
      def restore_state(data, emit: true)
        data = deep_symbolize(data || {})
        @last_term = data[:query]
        @last_options = deep_symbolize(data[:options] || {})
        @matches = deep_symbolize_array(data[:matches] || [])
        @current_match_index = data[:current_index]
        @current_match = deep_symbolize(data[:current_match])
        @current_query_key = @last_term ? query_key(@last_term, @last_options) : nil
        @last_error = data[:error]
        restore_decorations(data[:decorations] || [], emit: emit)
        state
      end

      # Restores only the current search decorations.
      # @param decorations [Array<Hash>]
      # @param emit [Boolean]
      # @return [Array<Hash>]
      def restore_decorations(decorations, emit: true)
        @decorations = deep_symbolize_array(decorations || [])
        emit_decoration_update(:restore) if emit
        @decorations
      end

      # Find next occurrence of term
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive
      # @return [Hash, nil] {row:, col:, length:} or nil
      def find_next(term, options = {})
        all = find_all(term, options)
        return reset_current_match if all.empty?

        query_key = query_key(term, options)
        if @current_match.nil? || @current_query_key != query_key
          @current_match_index = 0
        else
          @current_match_index = ((@current_match_index || 0) + 1) % all.length
        end

        @current_query_key = query_key
        @current_match = all[@current_match_index]
        @current_match
      end

      # Find previous occurrence
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive
      # @return [Hash, nil] {row:, col:, length:} or nil
      def find_previous(term, options = {})
        all = find_all(term, options)
        return reset_current_match if all.empty?

        query_key = query_key(term, options)
        if @current_match.nil? || @current_query_key != query_key
          @current_match_index = all.length - 1
        else
          @current_match_index = ((@current_match_index || 0) - 1) % all.length
        end

        @current_query_key = query_key
        @current_match = all[@current_match_index]
        @current_match
      end

      # Find all occurrences
      # @param term [String] search term
      # @param options [Hash] :regex, :whole_word, :case_sensitive, :scrollback, :decorations
      # @return [Array<Hash>] array of {row:, col:, length:}
      def find_all(term, options = {})
        if term.nil? || term.empty?
          store_search_state(term, options, [], nil)
          return []
        end

        matches = []
        buffer = @terminal.internal.buffer_set.active
        regex = build_regex(term, options)

        logical_lines(buffer, options).each do |logical_line|
          text = logical_line[:text]
          text.scan(regex) do
            m = Regexp.last_match
            match = MatchMapper.build(logical_line, m.begin(0), m[0])
            match[:captures] = capture_metadata(regex, logical_line, m) if match && options[:regex]
            matches << match if match
          end
        end

        store_search_state(term, options, matches, nil)
        apply_decorations(matches, options[:decorations]) if options.key?(:decorations)
        matches
      rescue RegexpError => e
        store_search_state(term, options, [], e.message)
        reset_decorations if options.key?(:decorations)
        []
      end

      def clear_decorations
        @current_match = nil
        @current_match_index = nil
        @current_query_key = nil
        reset_decorations
      end

      def dispose
        clear_decorations
        super
      end

      private

      def reset_current_match
        @current_match = nil
        @current_match_index = nil
        nil
      end

      def store_search_state(term, options, matches, error)
        @last_term = term
        @last_options = normalized_options(options)
        @matches = deep_dup(matches)
        @last_error = error
      end

      def normalized_options(options)
        normalized = {
          regex: options[:regex] == true,
          whole_word: options[:whole_word] == true,
          case_sensitive: options[:case_sensitive] == true,
          scrollback: options[:scrollback],
          include_scrollback: options[:include_scrollback] == true
        }
        normalized[:decorations] = deep_dup(options[:decorations]) if options.key?(:decorations)
        normalized
      end

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

      def capture_metadata(regex, logical_line, match_data)
        names_by_index = capture_names_by_index(regex)

        (1...match_data.length).filter_map do |index|
          next unless match_data[index]

          start_offset = match_data.begin(index)
          end_offset = match_data.end(index)
          position = MatchMapper.position_for_offset(logical_line[:segments], start_offset)
          ranges = MatchMapper.ranges_for_offsets(logical_line[:segments], start_offset, end_offset - start_offset)
          next unless position && ranges.any?

          {
            index: index,
            name: names_by_index[index],
            text: match_data[index],
            start: start_offset,
            end: end_offset,
            relative_start: start_offset - match_data.begin(0),
            relative_end: end_offset - match_data.begin(0),
            row: position[:row],
            line_index: position[:line_index],
            col: position[:col],
            length: ranges.sum { |range| range[:length] },
            ranges: ranges
          }.compact
        end
      end

      def capture_names_by_index(regex)
        regex.named_captures.each_with_object({}) do |(name, indexes), result|
          indexes.each { |index| result[index] = name }
        end
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

      def apply_decorations(matches, style)
        @decorations = style ? decorate(matches, style) : []
        emit_decoration_update(:update)
      end

      def reset_decorations
        @decorations = []
        emit_decoration_update(:clear)
      end

      def decorate(matches, style)
        matches.map { |match| match.merge(decoration: deep_dup(style)) }
      end

      def emit_decoration_update(action)
        @terminal.internal.emit(
          :search_decorations,
          {
            action: action,
            decorations: deep_dup(@decorations),
            state: state
          }
        )
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), copy| copy[key] = deep_dup(entry) }
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), result|
            result[key.to_sym] = deep_symbolize(entry)
          end
        when Array
          value.map { |entry| deep_symbolize(entry) }
        else
          value
        end
      end

      def deep_symbolize_array(value)
        Array(value).map { |entry| deep_symbolize(entry) }
      end
    end
  end
end
