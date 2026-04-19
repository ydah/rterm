# frozen_string_literal: true

module RTerm
  module Common
    # Builds Unicode width providers from standard Unicode data files.
    class UnicodeTableBuilder
      class GeneratedProvider
        def initialize(wide_ranges:, zero_width_ranges:, emoji_ranges:, emoji_variation_bases:,
                       text_variation_bases:, regional_indicator_ranges:, emoji_modifier_ranges:)
          @wide_ranges = merge_ranges(wide_ranges)
          @zero_width_ranges = merge_ranges(zero_width_ranges)
          @emoji_ranges = merge_ranges(emoji_ranges)
          @emoji_variation_bases = merge_ranges(emoji_variation_bases)
          @text_variation_bases = merge_ranges(text_variation_bases)
          @regional_indicator_ranges = merge_ranges(regional_indicator_ranges)
          @emoji_modifier_ranges = merge_ranges(emoji_modifier_ranges)
        end

        def char_width(codepoint)
          return grapheme_width(codepoint) if codepoint.is_a?(String)
          return 0 if control?(codepoint)
          return 0 if in_ranges?(codepoint, @zero_width_ranges)
          return 2 if in_ranges?(codepoint, @emoji_ranges)
          return 2 if in_ranges?(codepoint, @wide_ranges)

          1
        end

        def grapheme_width(cluster)
          codepoints = cluster.to_s.codepoints
          return 0 if codepoints.empty?

          base = codepoints.first
          return 1 if text_variation_sequence?(codepoints)
          return 2 if emoji_variation_sequence?(codepoints)
          return 2 if emoji_zwj_sequence?(codepoints)
          return 2 if regional_indicator_sequence?(codepoints)
          return 2 if emoji_modifier_sequence?(codepoints)
          return 2 if emoji_tag_sequence?(codepoints)

          char_width(base)
        end

        private

        def text_variation_sequence?(codepoints)
          codepoints.include?(0xFE0E) && in_ranges?(codepoints.first, @text_variation_bases)
        end

        def emoji_variation_sequence?(codepoints)
          codepoints.include?(0xFE0F) && in_ranges?(codepoints.first, @emoji_variation_bases)
        end

        def emoji_zwj_sequence?(codepoints)
          codepoints.include?(0x200D) && codepoints.any? { |codepoint| in_ranges?(codepoint, @emoji_ranges) }
        end

        def regional_indicator_sequence?(codepoints)
          codepoints.length == 2 && codepoints.all? { |codepoint| in_ranges?(codepoint, @regional_indicator_ranges) }
        end

        def emoji_modifier_sequence?(codepoints)
          in_ranges?(codepoints.first, @emoji_ranges) &&
            codepoints.any? { |codepoint| in_ranges?(codepoint, @emoji_modifier_ranges) }
        end

        def emoji_tag_sequence?(codepoints)
          return false unless in_ranges?(codepoints.first, @emoji_ranges)
          return false unless codepoints.last == 0xE007F

          codepoints[1...-1].all? { |codepoint| codepoint.between?(0xE0020, 0xE007E) }
        end

        def control?(codepoint)
          codepoint <= 0x1F || (codepoint >= 0x7F && codepoint <= 0x9F)
        end

        def merge_ranges(ranges)
          sorted = ranges.map { |range| [range[0], range[1]] }.sort_by(&:first)
          sorted.each_with_object([]) do |range, merged|
            if merged.empty? || range[0] > merged[-1][1] + 1
              merged << range
            else
              merged[-1][1] = [merged[-1][1], range[1]].max
            end
          end
        end

        def in_ranges?(codepoint, ranges)
          low = 0
          high = ranges.length - 1

          while low <= high
            mid = (low + high) / 2
            range = ranges[mid]

            if codepoint < range[0]
              high = mid - 1
            elsif codepoint > range[1]
              low = mid + 1
            else
              return true
            end
          end

          false
        end
      end

      def self.from_files(east_asian_width:, emoji_data: nil, emoji_variation_sequences: nil, ambiguous_width: 1)
        from_strings(
          east_asian_width: File.read(east_asian_width),
          emoji_data: emoji_data ? File.read(emoji_data) : nil,
          emoji_variation_sequences: emoji_variation_sequences ? File.read(emoji_variation_sequences) : nil,
          ambiguous_width: ambiguous_width
        )
      end

      def self.from_strings(east_asian_width:, emoji_data: nil, emoji_variation_sequences: nil, ambiguous_width: 1)
        wide_ranges = parse_east_asian_width(east_asian_width, ambiguous_width)
        emoji = parse_emoji_data(emoji_data.to_s)
        variation = parse_emoji_variation_sequences(emoji_variation_sequences.to_s)

        GeneratedProvider.new(
          wide_ranges: wide_ranges,
          zero_width_ranges: UnicodeHandler::ZERO_WIDTH_RANGES,
          emoji_ranges: emoji.fetch(:emoji_ranges),
          emoji_variation_bases: variation.fetch(:emoji_bases),
          text_variation_bases: variation.fetch(:text_bases),
          regional_indicator_ranges: emoji.fetch(:regional_indicator_ranges),
          emoji_modifier_ranges: emoji.fetch(:emoji_modifier_ranges)
        )
      end

      def self.parse_east_asian_width(data, ambiguous_width)
        data.each_line.each_with_object([]) do |line, ranges|
          body = line.split("#", 2).first.to_s.strip
          next if body.empty?

          range_text, property = body.split(";").map(&:strip)
          next unless %w[W F].include?(property) || (property == "A" && ambiguous_width == 2)

          ranges << parse_range(range_text)
        end
      end

      def self.parse_emoji_data(data)
        result = {
          emoji_ranges: [],
          regional_indicator_ranges: [],
          emoji_modifier_ranges: []
        }

        data.each_line do |line|
          body = line.split("#", 2).first.to_s.strip
          next if body.empty?

          range_text, property = body.split(";").map(&:strip)
          range = parse_range(range_text)
          case property
          when "Emoji_Presentation", "Extended_Pictographic"
            result[:emoji_ranges] << range
          when "Regional_Indicator"
            result[:regional_indicator_ranges] << range
          when "Emoji_Modifier"
            result[:emoji_modifier_ranges] << range
          end
        end

        result
      end

      def self.parse_emoji_variation_sequences(data)
        result = { emoji_bases: [], text_bases: [] }

        data.each_line do |line|
          body = line.split("#", 2).first.to_s.strip
          next if body.empty?

          sequence, style = body.split(";").map(&:strip)
          base, variation = sequence.split.map { |value| value.to_i(16) }
          case variation
          when 0xFE0F
            result[:emoji_bases] << [base, base] if style == "emoji style"
          when 0xFE0E
            result[:text_bases] << [base, base] if style == "text style"
          end
        end

        result
      end

      def self.parse_range(value)
        if value.include?("..")
          first, last = value.split("..", 2)
          [first.to_i(16), last.to_i(16)]
        else
          codepoint = value.to_i(16)
          [codepoint, codepoint]
        end
      end
    end
  end
end
