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
        @progressive_blocks = nil
        @eob_run = 0
        @adobe_transform = nil
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
          return finish_image if marker.nil? || marker == FINISH
          next if standalone_marker?(marker)

          length = read_u16
          payload = read(length - 2)
          result = decode_scan(payload) if marker == START_OF_SCAN
          return result if result

          process_segment(marker, payload)
        end
        finish_image
      end

      def process_segment(marker, payload)
        if marker == 0xdb
          parse_quantization(payload)
        elsif marker == 0xc4
          parse_huffman(payload)
        elsif marker == 0xee
          parse_adobe(payload)
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
          color_space: color_space,
          lossless: (true if lossless?),
          progressive: @frame_marker == 0xc2
        }.merge(extra).compact
      end

      def finish_image
        return progressive_image if progressive? && @progressive_blocks

        metadata
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

      def parse_adobe(payload)
        return unless payload.start_with?("Adobe") && payload.bytesize >= 12

        @adobe_transform = payload.getbyte(11)
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
        entropy = read_entropy_data
        if progressive_supported?
          decode_progressive_scan(EntropyReader.new(entropy))
          return nil
        end
        return metadata(format: :rgba, pixels: decode_lossless_pixels(EntropyReader.new(entropy))) if lossless_supported?
        return metadata unless baseline_supported?

        pixels = decode_pixels(EntropyReader.new(entropy))
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
        @spectral_start = payload.getbyte(offset).to_i
        @spectral_end = payload.getbyte(offset + 1).to_i
        successive = payload.getbyte(offset + 2).to_i
        @successive_high = successive >> 4
        @successive_low = successive & 0x0f
      end

      def baseline_supported?
        [0xc0, 0xc1].include?(@frame_marker) &&
          supported_precision? &&
          supported_component_count? &&
          @components.all? { |component| @quantization[component[:quantization_id]] }
      end

      def lossless?
        @frame_marker == 0xc3
      end

      def lossless_supported?
        lossless? &&
          supported_precision? &&
          supported_component_count? &&
          @components.all? { |component| component[:h] == 1 && component[:v] == 1 }
      end

      def progressive?
        @frame_marker == 0xc2
      end

      def progressive_supported?
        progressive? &&
          supported_precision? &&
          supported_component_count? &&
          @components.all? { |component| @quantization[component[:quantization_id]] }
      end

      def supported_precision?
        [8, 12].include?(@precision)
      end

      def supported_component_count?
        [1, 3, 4].include?(@components.length)
      end

      def read_entropy_data
        start = @index
        cursor = @index
        while cursor < @bytes.bytesize
          if @bytes.getbyte(cursor) == 0xff
            marker = @bytes.getbyte(cursor + 1)
            if marker == 0x00 || (0xd0..0xd7).include?(marker)
              cursor += 2
              next
            end
            @index = cursor
            return @bytes.byteslice(start, cursor - start).to_s
          end
          cursor += 1
        end
        @index = cursor
        @bytes.byteslice(start, cursor - start).to_s
      end

      def decode_progressive_scan(reader)
        prepare_progressive_blocks
        if @spectral_start.zero? && @spectral_end.zero?
          decode_progressive_dc_scan(reader)
        else
          decode_progressive_ac_scan(reader)
        end
      end

      def prepare_progressive_blocks
        return if @progressive_blocks

        max_h = @components.map { |component| component[:h] }.max
        max_v = @components.map { |component| component[:v] }.max
        @mcu_cols = (@width + (max_h * 8) - 1) / (max_h * 8)
        @mcu_rows = (@height + (max_v * 8) - 1) / (max_v * 8)
        @progressive_blocks = @components.each_with_object({}) do |component, result|
          rows = @mcu_rows * component[:v]
          cols = @mcu_cols * component[:h]
          result[component[:id]] = Array.new(rows) { Array.new(cols) { Array.new(64, 0) } }
        end
      end

      def progressive_image
        planes = @components.each_with_object({}) do |component, result|
          rows = @progressive_blocks[component[:id]].length
          cols = @progressive_blocks[component[:id]].first.length
          plane = Array.new(rows * 8) { Array.new(cols * 8, 0) }
          rows.times do |block_y|
            cols.times do |block_x|
              coefficients = dequantize(@progressive_blocks[component[:id]][block_y][block_x], component)
              draw_block(plane, idct(coefficients), block_x, block_y)
            end
          end
          result[component[:id]] = plane
        end
        metadata(format: :rgba, pixels: compose_pixels(planes))
      rescue ArgumentError
        metadata
      end

      def dequantize(coefficients, component)
        quantization = @quantization[component[:quantization_id]]
        coefficients.each_with_index.map { |value, position| value * quantization[position].to_i }
      end

      def decode_progressive_dc_scan(reader)
        @previous_dc = Hash.new(0) if @successive_high.zero?
        progressive_scan_blocks.each do |component, block_x, block_y|
          block = progressive_block(component, block_x, block_y)
          if @successive_high.zero?
            table = @huffman[:dc][component[:dc_table] || 0]
            raise ArgumentError, "missing JPEG Huffman table" unless table

            size = decode_huffman(reader, table)
            @previous_dc[component[:id]] += receive(reader, size)
            block[0] = @previous_dc[component[:id]] << @successive_low
          else
            bit = reader.bit
            raise ArgumentError, "truncated JPEG coefficient" if bit.nil?

            block[0] |= bit << @successive_low
          end
        end
      end

      def decode_progressive_ac_scan(reader)
        raise ArgumentError, "progressive AC scans must target one component" unless @scan_components.length == 1

        component = @scan_components.first
        @eob_run = 0
        progressive_scan_blocks.each do |_scan_component, block_x, block_y|
          block = progressive_block(component, block_x, block_y)
          if @successive_high.zero?
            decode_progressive_ac_initial(reader, component, block)
          else
            decode_progressive_ac_refinement(reader, component, block)
          end
        end
      end

      def decode_progressive_ac_initial(reader, component, block)
        return @eob_run -= 1 if @eob_run.positive?

        table = @huffman[:ac][component[:ac_table] || 0]
        raise ArgumentError, "missing JPEG Huffman table" unless table

        index = @spectral_start
        while index <= @spectral_end
          symbol = decode_huffman(reader, table)
          run = symbol >> 4
          size = symbol & 0x0f
          if size.zero?
            if run == 15
              index += 16
              next
            end
            @eob_run = (1 << run) + receive(reader, run) - 1
            break
          end

          index += run
          break if index > @spectral_end

          block[ZIGZAG[index]] = receive(reader, size) << @successive_low
          index += 1
        end
      end

      def decode_progressive_ac_refinement(reader, component, block)
        if @eob_run.positive?
          refine_nonzero_coefficients(reader, block, @spectral_start, @spectral_end)
          @eob_run -= 1
          return
        end

        table = @huffman[:ac][component[:ac_table] || 0]
        raise ArgumentError, "missing JPEG Huffman table" unless table

        index = @spectral_start
        while index <= @spectral_end
          coefficient_index = ZIGZAG[index]
          if block[coefficient_index].nonzero?
            refine_coefficient(reader, block, coefficient_index)
            index += 1
            next
          end

          symbol = decode_huffman(reader, table)
          run = symbol >> 4
          size = symbol & 0x0f
          if size.zero? && run != 15
            @eob_run = (1 << run) + receive(reader, run)
            refine_nonzero_coefficients(reader, block, index, @spectral_end)
            @eob_run -= 1
            break
          end

          new_coefficient = size.zero? ? nil : receive(reader, size) << @successive_low
          index = place_refined_coefficient(reader, block, index, run, new_coefficient)
        end
      end

      def place_refined_coefficient(reader, block, index, zero_run, new_coefficient)
        while index <= @spectral_end
          coefficient_index = ZIGZAG[index]
          if block[coefficient_index].nonzero?
            refine_coefficient(reader, block, coefficient_index)
          elsif zero_run.positive?
            zero_run -= 1
          else
            block[coefficient_index] = new_coefficient if new_coefficient
            return index + 1
          end
          index += 1
        end
        index
      end

      def refine_nonzero_coefficients(reader, block, start_index, end_index)
        start_index.upto(end_index) do |index|
          coefficient_index = ZIGZAG[index]
          refine_coefficient(reader, block, coefficient_index) if block[coefficient_index].nonzero?
        end
      end

      def refine_coefficient(reader, block, coefficient_index)
        bit = reader.bit
        raise ArgumentError, "truncated JPEG coefficient" if bit.nil?
        return if bit.zero?

        delta = 1 << @successive_low
        return unless (block[coefficient_index].abs & delta).zero?

        block[coefficient_index] += block[coefficient_index].positive? ? delta : -delta
      end

      def progressive_scan_blocks
        if @scan_components.length == 1
          component = @scan_components.first
          rows = @mcu_rows * component[:v]
          cols = @mcu_cols * component[:h]
          return Enumerator.new do |yielder|
            rows.times { |block_y| cols.times { |block_x| yielder << [component, block_x, block_y] } }
          end
        end

        Enumerator.new do |yielder|
          @mcu_rows.times do |mcu_y|
            @mcu_cols.times do |mcu_x|
              @scan_components.each do |component|
                component[:v].times do |vertical|
                  component[:h].times do |horizontal|
                    yielder << [component, (mcu_x * component[:h]) + horizontal, (mcu_y * component[:v]) + vertical]
                  end
                end
              end
            end
          end
        end
      end

      def progressive_block(component, block_x, block_y)
        @progressive_blocks.fetch(component[:id]).fetch(block_y).fetch(block_x)
      end

      def decode_lossless_pixels(reader)
        planes = lossless_planes
        @height.times do |y|
          @width.times do |x|
            @scan_components.each do |component|
              table = @huffman[:dc][component[:dc_table] || 0]
              raise ArgumentError, "missing JPEG Huffman table" unless table

              diff_size = decode_huffman(reader, table)
              diff = receive(reader, diff_size)
              predicted = lossless_prediction(planes[component[:id]], x, y)
              planes[component[:id]][y][x] = clamp_sample(predicted + diff)
            end
          end
        end
        compose_pixels(normalize_planes(planes))
      end

      def lossless_planes
        @components.each_with_object({}) do |component, result|
          result[component[:id]] = Array.new(@height) { Array.new(@width, nil) }
        end
      end

      def lossless_prediction(plane, x, y)
        return initial_lossless_prediction if x.zero? && y.zero?
        return plane[y][x - 1] if y.zero?
        return plane[y - 1][x] if x.zero?

        left = plane[y][x - 1]
        above = plane[y - 1][x]
        upper_left = plane[y - 1][x - 1]
        case @spectral_start
        when 1 then left
        when 2 then above
        when 3 then upper_left
        when 4 then left + above - upper_left
        when 5 then left + ((above - upper_left) / 2)
        when 6 then above + ((left - upper_left) / 2)
        when 7 then (left + above) / 2
        else raise ArgumentError, "unsupported JPEG lossless predictor"
        end
      end

      def initial_lossless_prediction
        1 << (@precision - @successive_low - 1)
      end

      def normalize_planes(planes)
        planes.transform_values do |plane|
          plane.map { |row| row.map { |value| normalize_sample(value << @successive_low) } }
        end
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
            normalize_sample((sum / 4.0).round + sample_center)
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

        return compose_four_component_pixels(planes) if @components.length == 4

        y_plane = planes[@components[0][:id]]
        cb_plane = planes[@components[1][:id]]
        cr_plane = planes[@components[2][:id]]
        Array.new(@height) do |y|
          Array.new(@width) do |x|
            if rgb_transform?
              rgb(sample(y_plane, x, y), sample(cb_plane, x, y), sample(cr_plane, x, y))
            else
              ycbcr(sample(y_plane, x, y), sample(cb_plane, x, y), sample(cr_plane, x, y))
            end
          end
        end
      end

      def compose_four_component_pixels(planes)
        first_plane = planes[@components[0][:id]]
        second_plane = planes[@components[1][:id]]
        third_plane = planes[@components[2][:id]]
        fourth_plane = planes[@components[3][:id]]
        Array.new(@height) do |y|
          Array.new(@width) do |x|
            first = sample(first_plane, x, y)
            second = sample(second_plane, x, y)
            third = sample(third_plane, x, y)
            fourth = sample(fourth_plane, x, y)
            ycck_transform? ? ycck(first, second, third, fourth) : cmyk(first, second, third, fourth)
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
        rgb(*ycbcr_rgb(y, cb, cr))
      end

      def ycbcr_rgb(y, cb, cr)
        cb -= 128
        cr -= 128
        [
          clamp(y + (1.402 * cr).round),
          clamp(y - (0.344_136 * cb).round - (0.714_136 * cr).round),
          clamp(y + (1.772 * cb).round)
        ]
      end

      def ycck(y, cb, cr, key)
        red, green, blue = ycbcr_rgb(y, cb, cr)
        cmyk(255 - red, 255 - green, 255 - blue, key)
      end

      def cmyk(cyan, magenta, yellow, key)
        [
          clamp(255 - [cyan + key, 255].min),
          clamp(255 - [magenta + key, 255].min),
          clamp(255 - [yellow + key, 255].min),
          255
        ]
      end

      def rgb(red, green, blue)
        [red, green, blue, 255]
      end

      def color_space
        return :grayscale if @components.length == 1
        return rgb_transform? ? :rgb : :ycbcr if @components.length == 3
        return ycck_transform? ? :ycck : :cmyk if @components.length == 4

        nil
      end

      def rgb_transform?
        @adobe_transform == 0
      end

      def ycck_transform?
        @adobe_transform == 2
      end

      def sample_center
        1 << (@precision - 1)
      end

      def sample_max
        (1 << @precision) - 1
      end

      def normalize_sample(value)
        return clamp(value) if @precision == 8

        clamp(((clamp_sample(value) * 255.0) / sample_max).round)
      end

      def clamp_sample(value)
        [[value, 0].max, sample_max].min
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
