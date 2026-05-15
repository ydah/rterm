# frozen_string_literal: true

module RTerm
  module Common
    class GifDecoder
      SIGNATURES = ["GIF87a", "GIF89a"].freeze
      INTERLACE_ROWS = [[0, 8], [4, 8], [2, 4], [1, 2]].freeze

      def self.decode(bytes)
        new(bytes).decode
      end

      def initialize(bytes)
        @bytes = bytes.to_s.b
        @index = 0
        @transparent_index = nil
        @delay = nil
      end

      def decode
        return nil unless gif?

        read_header
        read_logical_screen
        read_blocks
      rescue ArgumentError
        nil
      end

      private

      def gif?
        SIGNATURES.include?(@bytes[0, 6])
      end

      def read_header
        @version = read(6)
      end

      def read_logical_screen
        @screen_width = read_u16
        @screen_height = read_u16
        packed = read_byte
        @background_index = read_byte
        read_byte
        @global_table = color_table(1 << ((packed & 0x07) + 1)) if (packed & 0x80).positive?
      end

      def read_blocks
        loop do
          marker = read_byte
          case marker
          when 0x2c then return read_image
          when 0x21 then read_extension
          when 0x3b then return nil
          else
            raise ArgumentError, "invalid GIF block"
          end
        end
      end

      def read_extension
        label = read_byte
        if label == 0xf9
          read_graphic_control
        else
          read_sub_blocks
        end
      end

      def read_graphic_control
        size = read_byte
        data = read(size)
        read_byte
        packed, delay_low, delay_high, transparent = data.bytes
        @delay = delay_low.to_i + (delay_high.to_i << 8)
        @transparent_index = transparent if (packed.to_i & 0x01).positive?
      end

      def read_image
        left = read_u16
        top = read_u16
        width = read_u16
        height = read_u16
        packed = read_byte
        table = (packed & 0x80).positive? ? color_table(1 << ((packed & 0x07) + 1)) : @global_table
        interlaced = (packed & 0x40).positive?
        min_code_size = read_byte
        data = read_sub_blocks
        indices = decode_lzw(data, min_code_size, width * height)
        rows = indexed_rows(indices, table || [], width, height, interlaced)
        {
          format: :rgba,
          media_type: :gif,
          version: @version,
          width: width,
          height: height,
          screen_width: @screen_width,
          screen_height: @screen_height,
          left: left,
          top: top,
          delay: @delay,
          pixels: rows
        }.compact
      end

      def indexed_rows(indices, table, width, height, interlaced)
        rows = Array.new(height) { Array.new(width) { transparent_color } }
        source_row = 0
        row_order(height, interlaced).each do |row|
          width.times do |col|
            rows[row][col] = color(table, indices[(source_row * width) + col])
          end
          source_row += 1
        end
        rows
      end

      def row_order(height, interlaced)
        return (0...height).to_a unless interlaced

        INTERLACE_ROWS.flat_map do |start, step|
          rows = []
          row = start
          while row < height
            rows << row
            row += step
          end
          rows
        end
      end

      def color(table, index)
        return transparent_color if index.nil?

        rgba = table[index] || [0, 0, 0, 255]
        return [rgba[0], rgba[1], rgba[2], 0] if index == @transparent_index

        rgba
      end

      def transparent_color
        [0, 0, 0, 0]
      end

      def decode_lzw(data, min_code_size, limit)
        reader = BitReader.new(data)
        clear = 1 << min_code_size
        finish = clear + 1
        dictionary = initial_dictionary(clear)
        code_size = min_code_size + 1
        previous = nil
        output = []

        loop do
          code = reader.read(code_size)
          break if code.nil? || code == finish
          if code == clear
            dictionary = initial_dictionary(clear)
            code_size = min_code_size + 1
            previous = nil
            next
          end

          entry = dictionary[code] || (previous ? previous + [previous.first] : [])
          output.concat(entry)
          break if output.length >= limit

          if previous
            dictionary << previous + [entry.first]
            code_size += 1 if dictionary.length == (1 << code_size) && code_size < 12
          end
          previous = entry
        end

        output.first(limit)
      end

      def initial_dictionary(size)
        (0...size).map { |value| [value] } + [nil, nil]
      end

      def color_table(size)
        read(size * 3).bytes.each_slice(3).map { |red, green, blue| [red, green, blue, 255] }
      end

      def read_sub_blocks
        result = +""
        loop do
          length = read_byte
          break if length.zero?

          result << read(length)
        end
        result
      end

      def read_u16
        read(2).unpack1("v")
      end

      def read_byte
        byte = @bytes.getbyte(@index)
        raise ArgumentError, "truncated GIF" if byte.nil?

        @index += 1
        byte
      end

      def read(length)
        data = @bytes.byteslice(@index, length)
        raise ArgumentError, "truncated GIF" unless data && data.bytesize == length

        @index += length
        data
      end

      class BitReader
        def initialize(data)
          @bytes = data.bytes
          @bit = 0
        end

        def read(size)
          value = 0
          size.times do |offset|
            byte = @bytes[@bit / 8]
            return nil unless byte

            value |= ((byte >> (@bit % 8)) & 1) << offset
            @bit += 1
          end
          value
        end
      end
    end
  end
end
