# frozen_string_literal: true

require_relative "../base"
require_relative "../../common/event_emitter"

module RTerm
  module Addon
    class Ligatures < Base
      include Common::EventEmitter

      DEFAULT_PATTERNS = %w[
        === !== == != <= >= -> <- => =>> <=> <->
        ++ -- ** && || !! ?? ?: :: ::: ... .. www ffi ffl
      ].freeze

      def initialize(patterns: DEFAULT_PATTERNS, enabled: true)
        @patterns = normalize_patterns(patterns)
        @enabled = enabled
        @joiner_id = nil
      end

      attr_reader :patterns, :joiner_id

      def activate(terminal)
        super
        @joiner_id = terminal.register_character_joiner do |line, row|
          enabled? ? character_joiner_ranges(line, row: row) : []
        end
      end

      def enabled?
        @enabled
      end

      def enable
        @enabled = true
        emit(:change, state)
        true
      end

      def disable
        @enabled = false
        emit(:change, state)
        true
      end

      def state
        { enabled: enabled?, patterns: @patterns.dup, joiner_id: @joiner_id }
      end

      def register(pattern)
        normalized = pattern.to_s
        return false if normalized.empty? || @patterns.include?(normalized)

        @patterns << normalized
        sort_patterns!
        emit(:change, state)
        true
      end

      def deregister(pattern)
        removed = !!@patterns.delete(pattern.to_s)
        emit(:change, state) if removed
        removed
      end

      def ranges(text, row: nil)
        find_ranges(text.to_s, row: row)
      end

      def line_ranges(row)
        ensure_active!

        line = @terminal.buffer.active.get_line(row.to_i)
        return [] unless line

        ranges(line.to_string, row: row.to_i)
      end

      def character_joiner_ranges(text, row: nil)
        return [] unless enabled?

        ranges(text, row: row).map { |range| [range[:start], range[:end]] }
      end

      def on_change(&block)
        on(:change, &block)
      end

      def dispose
        @terminal&.deregister_character_joiner(@joiner_id) if @joiner_id
        @joiner_id = nil
        super
      end

      alias enabled enabled?
      alias registerPattern register
      alias deregisterPattern deregister
      alias lineRanges line_ranges
      alias characterJoinerRanges character_joiner_ranges
      alias onChange on_change

      private

      def ensure_active!
        raise RuntimeError, "Ligatures addon is not active" unless @terminal
      end

      def normalize_patterns(patterns)
        Array(patterns).map(&:to_s).reject(&:empty?).uniq.sort_by { |pattern| [-pattern.length, pattern] }
      end

      def sort_patterns!
        @patterns.sort_by! { |pattern| [-pattern.length, pattern] }
      end

      def find_ranges(text, row:)
        ranges = []
        index = 0
        while index < text.length
          match = pattern_at(text, index)
          if match
            ranges << { start: index, end: index + match.length, text: match, row: row }
            index += match.length
          else
            index += 1
          end
        end
        ranges
      end

      def pattern_at(text, index)
        @patterns.find { |pattern| text[index, pattern.length] == pattern }
      end
    end
  end
end
