# frozen_string_literal: true

module RTerm
  module Services
    class CharSizeService
      attr_reader :width, :height, :source

      def initialize(width: 0, height: 0)
        @width = width.to_f
        @height = height.to_f
        @source = @width.positive? && @height.positive? ? :measured : :unset
      end

      def measure(width:, height:)
        @width = width.to_f
        @height = height.to_f
        @source = :measured
        size
      end

      def estimate(font_size:, line_height: 1.0, letter_spacing: 0)
        font_size = positive_float(font_size, 13.0)
        line_height = positive_float(line_height, 1.0)
        @width = [(font_size * 0.6) + letter_spacing.to_f, 1.0].max
        @height = [font_size * line_height, 1.0].max
        @source = :estimated
        size
      end

      def estimate_from_options(options)
        values = options.respond_to?(:to_h) ? options.to_h : options
        estimate(
          font_size: values[:font_size] || values["font_size"],
          line_height: values[:line_height] || values["line_height"] || 1.0,
          letter_spacing: values[:letter_spacing] || values["letter_spacing"] || 0
        )
      end

      def measured?
        @source == :measured
      end

      def estimated?
        @source == :estimated
      end

      def ready?
        @width.positive? && @height.positive?
      end

      alias measured measured?
      alias estimated estimated?
      alias ready ready?

      def size
        { width: @width, height: @height, source: @source }
      end

      private

      def positive_float(value, fallback)
        number = value.to_f
        number.positive? ? number : fallback
      end
    end
  end
end
