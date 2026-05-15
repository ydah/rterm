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

        rows = unfiltered_rows(Zlib::Inflate.inflate(@idat))
        {
          format: :rgba,
          media_type: :png,
          width: @width,
          height: @height,
          bit_depth: @bit_depth,
          color_type: @color_type,
          pixels: rows.map { |row| rgba_row(row) }
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
        return false unless @compression == 0 && @filter == 0 && @interlace == 0

        SUPPORTED_DEPTHS.fetch(@color_type, []).include?(@bit_depth)
      end

      def unfiltered_rows(data)
        rows = []
        previous = Array.new(scanline_bytes, 0)
        offset = 0

        @height.times do
          filter = data.getbyte(offset)
          offset += 1
          current = data.byteslice(offset, scanline_bytes).to_s.bytes
          offset += scanline_bytes
          row = unfilter_row(filter, current, previous)
          rows << row
          previous = row
        end

        rows
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

      def rgba_row(row)
        case @color_type
        when 0 then grayscale_row(row)
        when 2 then truecolor_row(row)
        when 3 then palette_row(row)
        when 4 then grayscale_alpha_row(row)
        when 6 then rgba_color_row(row)
        else
          []
        end
      end

      def grayscale_row(row)
        sample_values(row, 1).map do |gray|
          alpha = transparent_gray?(gray) ? 0 : 255
          [gray, gray, gray, alpha]
        end
      end

      def truecolor_row(row)
        sample_values(row, 3).map do |red, green, blue|
          alpha = transparent_rgb?(red, green, blue) ? 0 : 255
          [red, green, blue, alpha]
        end
      end

      def palette_row(row)
        packed_indices(row).map do |index|
          color = @palette[index] || [0, 0, 0, 255]
          alpha = @transparency&.getbyte(index)
          [color[0], color[1], color[2], alpha.nil? ? color[3] : alpha]
        end
      end

      def grayscale_alpha_row(row)
        sample_values(row, 2).map { |gray, alpha| [gray, gray, gray, alpha] }
      end

      def rgba_color_row(row)
        sample_values(row, 4).map { |red, green, blue, alpha| [red, green, blue, alpha] }
      end

      def sample_values(row, samples_per_pixel)
        values = if @bit_depth == 16
          row.each_slice(2).map { |high, low| (((high.to_i << 8) + low.to_i) / 257.0).round }
        else
          row
        end
        values.each_slice(samples_per_pixel).first(@width)
      end

      def packed_indices(row)
        return row.first(@width) if @bit_depth == 8

        mask = (1 << @bit_depth) - 1
        result = []
        row.each do |byte|
          shift = 8 - @bit_depth
          while shift >= 0 && result.length < @width
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

      def scanline_bytes
        ((@width * bits_per_pixel) + 7) / 8
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
