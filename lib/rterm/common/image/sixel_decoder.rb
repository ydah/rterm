# frozen_string_literal: true

module RTerm
  module Common
    class SixelDecoder
      PARAM_CHARS = ("0".."9").to_a + [";"]
      DEFAULT_PALETTE = {
        0 => [0, 0, 0, 0],
        1 => [0, 0, 0, 255],
        2 => [255, 0, 0, 255],
        3 => [0, 255, 0, 255],
        4 => [0, 0, 255, 255],
        5 => [255, 255, 0, 255],
        6 => [255, 0, 255, 255],
        7 => [0, 255, 255, 255]
      }.freeze

      def self.decode(image)
        new(image).decode
      end

      def initialize(image)
        @image = image.to_h
        @data = @image[:data].to_s
        @palette = DEFAULT_PALETTE.transform_values(&:dup)
        @color = 1
        @x = 0
        @band = 0
        @pixels = initial_pixels
      end

      def decode
        index = 0
        while index < @data.length
          index = process_byte(index)
        end

        {
          protocol: :sixel,
          format: :indexed_rgba,
          width: width,
          height: height,
          palette: deep_dup(@palette),
          pixels: deep_dup(@pixels),
          raster: deep_dup(@image[:raster] || {})
        }
      end

      private

      def process_byte(index)
        case @data[index]
        when '"'
          _values, next_index = command_params(index + 1)
          next_index
        when "#"
          values, next_index = command_params(index + 1)
          set_color(values)
          next_index
        when "!"
          count, next_index = repeat_count(index + 1)
          return next_index unless sixel_data_char?(@data[next_index])

          plot_sixel(@data[next_index], count)
          next_index + 1
        when "$"
          @x = 0
          index + 1
        when "-"
          @x = 0
          @band += 1
          ensure_height((@band + 1) * 6)
          index + 1
        else
          plot_sixel(@data[index], 1) if sixel_data_char?(@data[index])
          index + 1
        end
      end

      def set_color(values)
        index = values[0]
        return unless index

        @color = index
        return unless values[1] == 2 && values.length >= 5

        @palette[index] = values[2, 3].map { |value| percent_to_byte(value) } + [255]
      end

      def plot_sixel(char, count)
        mask = char.ord - 0x3F
        count.times do
          ensure_width(@x + 1)
          6.times do |bit|
            next if (mask & (1 << bit)).zero?

            y = (@band * 6) + bit
            ensure_height(y + 1)
            @pixels[y][@x] = @color
          end
          @x += 1
        end
      end

      def initial_pixels
        Array.new(initial_height) { Array.new(initial_width) }
      end

      def initial_width
        raster_value(:pixel_width) || geometry_value(:cell_width) || 1
      end

      def initial_height
        raster_value(:pixel_height) || geometry_value(:pixel_height) || 6
      end

      def width
        @pixels.map(&:length).max || 0
      end

      def height
        @pixels.length
      end

      def ensure_width(next_width)
        return if next_width <= width

        @pixels.each { |row| row.concat(Array.new(next_width - row.length)) }
      end

      def ensure_height(next_height)
        return if next_height <= height

        (next_height - height).times { @pixels << Array.new(width) }
      end

      def raster_value(key)
        value = (@image[:raster] || {})[key]
        value.to_i.positive? ? value.to_i : nil
      end

      def geometry_value(key)
        value = (@image[:geometry] || {})[key]
        value.to_i.positive? ? value.to_i : nil
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

      def percent_to_byte(value)
        [[value.to_i, 0].max, 100].min * 255 / 100
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key] = deep_dup(item) }
        when Array
          value.map { |item| deep_dup(item) }
        else
          value
        end
      end
    end
  end
end
