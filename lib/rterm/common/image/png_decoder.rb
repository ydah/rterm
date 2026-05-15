# frozen_string_literal: true

require "zlib"

module RTerm
  module Common
    class PngDecoder
      SIGNATURE = "\x89PNG\r\n\x1A\n".b
      COLOR_SAMPLES = {
        0 => 1,
        2 => 3,
        3 => 1,
        4 => 2,
        6 => 4
      }.freeze
      SUPPORTED_DEPTHS = {
        0 => [8, 16],
        2 => [8, 16],
        3 => [1, 2, 4, 8],
        4 => [8, 16],
        6 => [8, 16]
      }.freeze
      ADAM7_PASSES = [
        [0, 0, 8, 8],
        [4, 0, 8, 8],
        [0, 4, 4, 8],
        [2, 0, 4, 4],
        [0, 2, 2, 4],
        [1, 0, 2, 2],
        [0, 1, 1, 2]
      ].freeze

      def self.decode(bytes)
        new(bytes).decode
      end

      def initialize(bytes)
        @bytes = bytes.to_s.b
        @palette = []
        @transparency = nil
        @idat = +""
      end

      def decode
        return nil unless png?

        parse_chunks
        return nil unless supported?

        rows = pixel_rows(Zlib::Inflate.inflate(@idat))
        {
          format: :rgba,
          media_type: :png,
          width: @width,
          height: @height,
          bit_depth: @bit_depth,
          color_type: @color_type,
          pixels: rows
        }
      rescue Zlib::Error, ArgumentError
        nil
      end

      private

      def png?
        @bytes.start_with?(SIGNATURE)
      end

      def parse_chunks
        index = SIGNATURE.bytesize
        while index + 12 <= @bytes.bytesize
          length = @bytes[index, 4].unpack1("N")
          type = @bytes[index + 4, 4]
          data = @bytes[index + 8, length]
          break unless data && index + 12 + length <= @bytes.bytesize

          process_chunk(type, data)
          index += 12 + length
          break if type == "IEND"
        end
      end

      def process_chunk(type, data)
        case type
        when "IHDR"
          parse_header(data)
        when "PLTE"
          @palette = data.bytes.each_slice(3).map { |red, green, blue| [red, green, blue, 255] }
        when "tRNS"
          @transparency = data
        when "IDAT"
          @idat << data
        end
      end

      def parse_header(data)
        @width, @height, @bit_depth, @color_type, @compression, @filter, @interlace = data.unpack("NNCCCCC")
      end

      def supported?
        return false unless @width.to_i.positive? && @height.to_i.positive?
        return false unless @compression == 0 && @filter == 0 && [0, 1].include?(@interlace)

        SUPPORTED_DEPTHS.fetch(@color_type, []).include?(@bit_depth)
      end

      def pixel_rows(data)
        return unfiltered_rows(data, @width, @height).first.map { |row| rgba_row(row, @width) } if @interlace.zero?

        interlaced_pixel_rows(data)
      end

      def unfiltered_rows(data, width, height, offset = 0)
        rows = []
        bytes = scanline_bytes(width)
        previous = Array.new(bytes, 0)

        height.times do
          filter = data.getbyte(offset)
          offset += 1
          current = data.byteslice(offset, bytes).to_s.bytes
          offset += bytes
          row = unfilter_row(filter, current, previous)
          rows << row
          previous = row
        end

        [rows, offset]
      end

      def interlaced_pixel_rows(data)
        pixels = Array.new(@height) { Array.new(@width) { [0, 0, 0, 0] } }
        offset = 0
        ADAM7_PASSES.each do |start_x, start_y, step_x, step_y|
          width = pass_size(@width, start_x, step_x)
          height = pass_size(@height, start_y, step_y)
          next if width.zero? || height.zero?

          rows, offset = unfiltered_rows(data, width, height, offset)
          rows.each_with_index do |row, pass_y|
            rgba_row(row, width).each_with_index do |color, pass_x|
              x = start_x + (pass_x * step_x)
              y = start_y + (pass_y * step_y)
              pixels[y][x] = color if x < @width && y < @height
            end
          end
        end
        pixels
      end

      def pass_size(size, start, step)
        return 0 if size <= start

        ((size - start) + step - 1) / step
      end

      def unfilter_row(filter, current, previous)
        case filter
        when 0 then current
        when 1 then sub_filter(current)
        when 2 then up_filter(current, previous)
        when 3 then average_filter(current, previous)
        when 4 then paeth_filter(current, previous)
        else
          raise ArgumentError, "unsupported PNG filter: #{filter}"
        end
      end

      def sub_filter(current)
        current.each_index.map do |index|
          (current[index] + (index >= filter_bpp ? current[index - filter_bpp] : 0)) & 0xff
        end
      end

      def up_filter(current, previous)
        current.each_index.map { |index| (current[index] + previous[index].to_i) & 0xff }
      end

      def average_filter(current, previous)
        current.each_index.map do |index|
          left = index >= filter_bpp ? current[index - filter_bpp] : 0
          up = previous[index].to_i
          (current[index] + ((left + up) / 2)) & 0xff
        end
      end

      def paeth_filter(current, previous)
        current.each_index.map do |index|
          left = index >= filter_bpp ? current[index - filter_bpp] : 0
          up = previous[index].to_i
          upper_left = index >= filter_bpp ? previous[index - filter_bpp].to_i : 0
          (current[index] + paeth(left, up, upper_left)) & 0xff
        end
      end

      def paeth(left, up, upper_left)
        estimate = left + up - upper_left
        left_distance = (estimate - left).abs
        up_distance = (estimate - up).abs
        upper_left_distance = (estimate - upper_left).abs
        return left if left_distance <= up_distance && left_distance <= upper_left_distance
        return up if up_distance <= upper_left_distance

        upper_left
      end

      def rgba_row(row, pixel_count)
        case @color_type
        when 0 then grayscale_row(row, pixel_count)
        when 2 then truecolor_row(row, pixel_count)
        when 3 then palette_row(row, pixel_count)
        when 4 then grayscale_alpha_row(row, pixel_count)
        when 6 then rgba_color_row(row, pixel_count)
        else
          []
        end
      end

      def grayscale_row(row, pixel_count)
        sample_values(row, 1, pixel_count).map do |gray|
          alpha = transparent_gray?(gray) ? 0 : 255
          [gray, gray, gray, alpha]
        end
      end

      def truecolor_row(row, pixel_count)
        sample_values(row, 3, pixel_count).map do |red, green, blue|
          alpha = transparent_rgb?(red, green, blue) ? 0 : 255
          [red, green, blue, alpha]
        end
      end

      def palette_row(row, pixel_count)
        packed_indices(row, pixel_count).map do |index|
          color = @palette[index] || [0, 0, 0, 255]
          alpha = @transparency&.getbyte(index)
          [color[0], color[1], color[2], alpha.nil? ? color[3] : alpha]
        end
      end

      def grayscale_alpha_row(row, pixel_count)
        sample_values(row, 2, pixel_count).map { |gray, alpha| [gray, gray, gray, alpha] }
      end

      def rgba_color_row(row, pixel_count)
        sample_values(row, 4, pixel_count).map { |red, green, blue, alpha| [red, green, blue, alpha] }
      end

      def sample_values(row, samples_per_pixel, pixel_count)
        values = if @bit_depth == 16
          row.each_slice(2).map { |high, low| (((high.to_i << 8) + low.to_i) / 257.0).round }
        else
          row
        end
        values.each_slice(samples_per_pixel).first(pixel_count)
      end

      def packed_indices(row, pixel_count)
        return row.first(pixel_count) if @bit_depth == 8

        mask = (1 << @bit_depth) - 1
        result = []
        row.each do |byte|
          shift = 8 - @bit_depth
          while shift >= 0 && result.length < pixel_count
            result << ((byte >> shift) & mask)
            shift -= @bit_depth
          end
        end
        result
      end

      def transparent_gray?(gray)
        return false unless @transparency && @transparency.bytesize >= 2

        gray == transparency_samples.first
      end

      def transparent_rgb?(red, green, blue)
        return false unless @transparency && @transparency.bytesize >= 6

        [red, green, blue] == transparency_samples.first(3)
      end

      def transparency_samples
        @transparency.unpack("n*").map { |sample| sample > 255 ? (sample / 257.0).round : sample }
      end

      def scanline_bytes(width)
        ((width * bits_per_pixel) + 7) / 8
      end

      def bits_per_pixel
        COLOR_SAMPLES.fetch(@color_type) * @bit_depth
      end

      def filter_bpp
        [bits_per_pixel / 8, 1].max
      end
    end
  end
end
