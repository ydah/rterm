# frozen_string_literal: true

module RTerm
  module Common
    class JpegDecoder
      START = "\xff\xd8".b
      FINISH = 0xd9
      START_OF_SCAN = 0xda
      SOF_MARKERS = [
        0xc0, 0xc1, 0xc2, 0xc3,
        0xc5, 0xc6, 0xc7,
        0xc9, 0xca, 0xcb,
        0xcd, 0xce, 0xcf
      ].freeze
      ZIGZAG = [
        0, 1, 8, 16, 9, 2, 3, 10,
        17, 24, 32, 25, 18, 11, 4, 5,
        12, 19, 26, 33, 40, 48, 41, 34,
        27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36,
        29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46,
        53, 60, 61, 54, 47, 55, 62, 63
      ].freeze

      def self.decode(bytes)
        new(bytes).decode
      end

      def initialize(bytes)
        @bytes = bytes.to_s.b
        @index = 2
        @quantization = {}
        @huffman = { dc: {}, ac: {} }
        @components = []
        @scan_components = []
        @previous_dc = Hash.new(0)
      end

      def decode
        return nil unless jpeg?

        scan_segments
      rescue ArgumentError
        nil
      end

      private

      def jpeg?
        @bytes.start_with?(START)
      end

      def scan_segments
        until @index >= @bytes.bytesize
          marker = next_marker
          return metadata if marker.nil? || marker == FINISH
          next if standalone_marker?(marker)

          length = read_u16
          payload = read(length - 2)
          return decode_scan(payload) if marker == START_OF_SCAN

          process_segment(marker, payload)
        end
        metadata
      end

      def process_segment(marker, payload)
        if marker == 0xdb
          parse_quantization(payload)
        elsif marker == 0xc4
          parse_huffman(payload)
        elsif SOF_MARKERS.include?(marker)
          parse_frame(marker, payload)
        end
      end

      def parse_frame(marker, payload)
        @frame_marker = marker
        @precision = payload.getbyte(0)
        @height = payload.byteslice(1, 2).unpack1("n")
        @width = payload.byteslice(3, 2).unpack1("n")
        count = payload.getbyte(5)
        offset = 6
        @components = count.times.map do
          id = payload.getbyte(offset)
          sampling = payload.getbyte(offset + 1)
          quantization_id = payload.getbyte(offset + 2)
          offset += 3
          {
            id: id,
            h: sampling >> 4,
            v: sampling & 0x0f,
            quantization_id: quantization_id
          }
        end
      end

      def metadata(extra = {})
        {
          format: extra[:pixels] ? :rgba : :sampled,
          media_type: :jpeg,
          width: @width,
          height: @height,
          precision: @precision,
          components: @components.length,
          progressive: @frame_marker == 0xc2
        }.merge(extra).compact
      end

      def parse_quantization(payload)
        offset = 0
        while offset < payload.bytesize
          info = payload.getbyte(offset)
          offset += 1
          precision = info >> 4
          table_id = info & 0x0f
          count = precision.zero? ? 64 : 128
          values = precision.zero? ? payload.byteslice(offset, count).bytes : payload.byteslice(offset, count).unpack("n*")
          offset += count
          table = Array.new(64)
          values.each_with_index { |value, index| table[ZIGZAG[index]] = value }
          @quantization[table_id] = table
        end
      end

      def parse_huffman(payload)
        offset = 0
        while offset < payload.bytesize
          info = payload.getbyte(offset)
          offset += 1
          table_class = info >> 4
          table_id = info & 0x0f
          counts = payload.byteslice(offset, 16).bytes
          offset += 16
          symbols = payload.byteslice(offset, counts.sum).bytes
          offset += counts.sum
          type = table_class.zero? ? :dc : :ac
          @huffman[type][table_id] = build_huffman(counts, symbols)
        end
      end

      def build_huffman(counts, symbols)
        code = 0
        index = 0
        entries = []
        counts.each_with_index do |count, length_index|
          length = length_index + 1
          count.times do
            entries << { code: code, length: length, symbol: symbols[index] }
            code += 1
            index += 1
          end
          code <<= 1
        end
        entries
      end

      def decode_scan(payload)
        parse_scan_header(payload)
        return metadata unless baseline_supported?

        pixels = decode_pixels(EntropyReader.new(scan_data))
        metadata(format: :rgba, pixels: pixels)
      rescue ArgumentError
        metadata
      end

      def parse_scan_header(payload)
        count = payload.getbyte(0)
        offset = 1
        @scan_components = count.times.map do
          id = payload.getbyte(offset)
          selectors = payload.getbyte(offset + 1)
          offset += 2
          component = @components.find { |item| item[:id] == id } || {}
          component.merge(dc_table: selectors >> 4, ac_table: selectors & 0x0f)
        end
      end

      def baseline_supported?
        @frame_marker == 0xc0 &&
          @precision == 8 &&
          [1, 3].include?(@components.length) &&
          @components.all? { |component| @quantization[component[:quantization_id]] }
      end

      def scan_data
        finish = @bytes.index("\xff\xd9".b, @index) || @bytes.bytesize
        @bytes.byteslice(@index, finish - @index).to_s
      end

      def decode_pixels(reader)
        max_h = @components.map { |component| component[:h] }.max
        max_v = @components.map { |component| component[:v] }.max
        mcu_cols = (@width + (max_h * 8) - 1) / (max_h * 8)
        mcu_rows = (@height + (max_v * 8) - 1) / (max_v * 8)
        planes = component_planes(mcu_cols, mcu_rows)

        mcu_rows.times do |mcu_y|
          mcu_cols.times do |mcu_x|
            @components.each do |component|
              component[:v].times do |vertical|
                component[:h].times do |horizontal|
                  block = decode_block(reader, component)
                  draw_block(planes[component[:id]], block, (mcu_x * component[:h]) + horizontal, (mcu_y * component[:v]) + vertical)
                end
              end
            end
          end
        end

        compose_pixels(planes)
      end

      def component_planes(mcu_cols, mcu_rows)
        @components.each_with_object({}) do |component, result|
          result[component[:id]] = Array.new(mcu_rows * component[:v] * 8) { Array.new(mcu_cols * component[:h] * 8, 0) }
        end
      end

      def decode_block(reader, component)
        dc_table = @huffman[:dc][component[:dc_table] || 0]
        ac_table = @huffman[:ac][component[:ac_table] || 0]
        raise ArgumentError, "missing JPEG Huffman table" unless dc_table && ac_table

        coefficients = Array.new(64, 0)
        dc_size = decode_huffman(reader, dc_table)
        @previous_dc[component[:id]] += receive(reader, dc_size)
        coefficients[0] = @previous_dc[component[:id]]
        index = 1
        while index < 64
          symbol = decode_huffman(reader, ac_table)
          break if symbol.zero?

          run = symbol >> 4
          size = symbol & 0x0f
          index += run
          break if index >= 64

          coefficients[ZIGZAG[index]] = receive(reader, size)
          index += 1
        end

        quantization = @quantization[component[:quantization_id]]
        idct(coefficients.each_with_index.map { |value, position| value * quantization[position].to_i })
      end

      def decode_huffman(reader, table)
        code = 0
        (1..16).each do |length|
          bit = reader.bit
          raise ArgumentError, "truncated JPEG entropy data" if bit.nil?

          code = (code << 1) | bit
          found = table.find { |entry| entry[:length] == length && entry[:code] == code }
          return found[:symbol] if found
        end
        raise ArgumentError, "invalid JPEG Huffman code"
      end

      def receive(reader, size)
        return 0 if size.zero?

        value = 0
        size.times do
          bit = reader.bit
          raise ArgumentError, "truncated JPEG coefficient" if bit.nil?

          value = (value << 1) | bit
        end
        value < (1 << (size - 1)) ? value - ((1 << size) - 1) : value
      end

      def idct(coefficients)
        Array.new(8) do |y|
          Array.new(8) do |x|
            sum = 0.0
            8.times do |v|
              8.times do |u|
                cu = u.zero? ? Math.sqrt(0.5) : 1.0
                cv = v.zero? ? Math.sqrt(0.5) : 1.0
                sum += cu * cv * coefficients[(v * 8) + u] *
                       Math.cos(((2 * x + 1) * u * Math::PI) / 16.0) *
                       Math.cos(((2 * y + 1) * v * Math::PI) / 16.0)
              end
            end
            clamp((sum / 4.0).round + 128)
          end
        end
      end

      def draw_block(plane, block, block_x, block_y)
        8.times do |row|
          8.times do |col|
            y = (block_y * 8) + row
            x = (block_x * 8) + col
            plane[y][x] = block[row][col] if plane[y] && x < plane[y].length
          end
        end
      end

      def compose_pixels(planes)
        if @components.length == 1
          gray = planes[@components.first[:id]]
          return Array.new(@height) { |y| Array.new(@width) { |x| grayscale(gray, x, y) } }
        end

        y_plane = planes[@components[0][:id]]
        cb_plane = planes[@components[1][:id]]
        cr_plane = planes[@components[2][:id]]
        Array.new(@height) do |y|
          Array.new(@width) do |x|
            ycbcr(sample(y_plane, x, y), sample(cb_plane, x, y), sample(cr_plane, x, y))
          end
        end
      end

      def sample(plane, x, y)
        source_y = y * plane.length / @height
        source_x = x * plane.first.length / @width
        plane[source_y][source_x]
      end

      def grayscale(plane, x, y)
        value = sample(plane, x, y)
        [value, value, value, 255]
      end

      def ycbcr(y, cb, cr)
        cb -= 128
        cr -= 128
        [
          clamp(y + (1.402 * cr).round),
          clamp(y - (0.344_136 * cb).round - (0.714_136 * cr).round),
          clamp(y + (1.772 * cb).round),
          255
        ]
      end

      def clamp(value)
        [[value, 0].max, 255].min
      end

      def next_marker
        @index += 1 while @index < @bytes.bytesize && @bytes.getbyte(@index) != 0xff
        @index += 1 while @index < @bytes.bytesize && @bytes.getbyte(@index) == 0xff
        marker = @bytes.getbyte(@index)
        @index += 1
        marker
      end

      def standalone_marker?(marker)
        marker == 0x01 || (0xd0..0xd7).include?(marker)
      end

      def read_u16
        data = read(2)
        data.unpack1("n")
      end

      def read(length)
        data = @bytes.byteslice(@index, length)
        raise ArgumentError, "truncated JPEG" unless data && data.bytesize == length

        @index += length
        data
      end

      class EntropyReader
        def initialize(data)
          @data = data
          @index = 0
          @bits = []
        end

        def bit
          fill_bits if @bits.empty?
          @bits.shift
        end

        private

        def fill_bits
          byte = @data.getbyte(@index)
          return if byte.nil?

          @index += 1
          if byte == 0xff
            marker = @data.getbyte(@index)
            @index += 1 if marker == 0x00
          end
          7.downto(0) { |shift| @bits << ((byte >> shift) & 1) }
        end
      end
    end
  end
end
