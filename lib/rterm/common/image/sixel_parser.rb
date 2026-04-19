# frozen_string_literal: true

module RTerm
  module Common
    # Parses enough Sixel structure for headless placement and serialization.
    class SixelParser
      PARAM_CHARS = ("0".."9").to_a + [";"]

      def self.parse(data, params: [])
        new(data.to_s, params).parse
      end

      def initialize(data, params)
        @data = data
        @params = params
      end

      def parse
        {
          protocol: :sixel,
          params: @params,
          data: @data,
          raster: raster_attributes,
          geometry: estimate_geometry
        }
      end

      private

      def raster_attributes
        return {} unless @data.start_with?('"')

        values, = command_params(1)
        {
          pan: values[0],
          pad: values[1],
          pixel_width: values[2],
          pixel_height: values[3]
        }.compact
      end

      def estimate_geometry
        max_width = 0
        x = 0
        band = 0
        i = 0

        while i < @data.length
          ch = @data[i]
          case ch
          when '"'
            _values, i = command_params(i + 1)
            next
          when "#"
            _values, i = command_params(i + 1)
            next
          when "!"
            count, next_index = repeat_count(i + 1)
            if sixel_data_char?(@data[next_index])
              x += count
              i = next_index + 1
              next
            end
            i = next_index
            next
          when "$"
            max_width = [max_width, x].max
            x = 0
          when "-"
            max_width = [max_width, x].max
            x = 0
            band += 1
          else
            x += 1 if sixel_data_char?(ch)
          end
          i += 1
        end

        max_width = [max_width, x].max
        { cell_width: max_width, pixel_height: (band + 1) * 6 }
      end

      def command_params(index)
        start = index
        index += 1 while index < @data.length && PARAM_CHARS.include?(@data[index])
        values = @data[start...index].to_s.split(";").map { |value| value.empty? ? nil : value.to_i }
        [values, index]
      end

      def repeat_count(index)
        start = index
        index += 1 while index < @data.length && @data[index].between?("0", "9")
        count = @data[start...index].to_s.to_i
        [count.positive? ? count : 1, index]
      end

      def sixel_data_char?(ch)
        return false unless ch

        code = ch.ord
        code >= 0x3F && code <= 0x7E
      end
    end
  end
end
