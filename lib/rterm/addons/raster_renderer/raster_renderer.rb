# frozen_string_literal: true

require_relative "../renderer_lifecycle"
require_relative "../../common/image/iterm2_decoder"
require_relative "../../common/image/sixel_decoder"

module RTerm
  module Addon
    class RasterRenderer < RendererLifecycle
      DEFAULT_CAPABILITIES = {
        raster_buffer: true,
        cursor_animation: true,
        image_composition: true,
        export_ppm: true
      }.freeze
      RENDERER_TYPE = :raster
      BASIC_GLYPHS = {
        "0" => %w[111 101 101 101 111],
        "1" => %w[010 110 010 010 111],
        "2" => %w[111 001 111 100 111],
        "3" => %w[111 001 111 001 111],
        "4" => %w[101 101 111 001 001],
        "5" => %w[111 100 111 001 111],
        "6" => %w[111 100 111 101 111],
        "7" => %w[111 001 010 010 010],
        "8" => %w[111 101 111 101 111],
        "9" => %w[111 101 111 001 111],
        "A" => %w[010 101 111 101 101],
        "B" => %w[110 101 110 101 110],
        "C" => %w[111 100 100 100 111],
        "D" => %w[110 101 101 101 110],
        "E" => %w[111 100 110 100 111],
        "F" => %w[111 100 110 100 100],
        "G" => %w[111 100 101 101 111],
        "H" => %w[101 101 111 101 101],
        "I" => %w[111 010 010 010 111],
        "J" => %w[001 001 001 101 111],
        "K" => %w[101 101 110 101 101],
        "L" => %w[100 100 100 100 111],
        "M" => %w[101 111 111 101 101],
        "N" => %w[101 111 111 111 101],
        "O" => %w[111 101 101 101 111],
        "P" => %w[111 101 111 100 100],
        "Q" => %w[111 101 101 111 001],
        "R" => %w[111 101 111 110 101],
        "S" => %w[111 100 111 001 111],
        "T" => %w[111 010 010 010 010],
        "U" => %w[101 101 101 101 111],
        "V" => %w[101 101 101 101 010],
        "W" => %w[101 101 111 111 101],
        "X" => %w[101 101 010 101 101],
        "Y" => %w[101 101 010 010 010],
        "Z" => %w[111 001 010 100 111],
        "." => %w[000 000 000 000 010],
        "-" => %w[000 000 111 000 000],
        "_" => %w[000 000 000 000 111],
        "/" => %w[001 001 010 100 100],
        "\\" => %w[100 100 010 001 001],
        ":" => %w[000 010 000 010 000]
      }.freeze

      attr_reader :frame, :cursor_visible, :rendered_at

      def initialize(options = {})
        super
        @cell_width = positive_integer(@options[:cell_width], 8)
        @cell_height = positive_integer(@options[:cell_height], 16)
        @draw_text = @options.fetch(:draw_text, true) != false
        @draw_images = @options.fetch(:draw_images, true) != false
        @draw_cursor = @options.fetch(:draw_cursor, true) != false
        @glyph_renderer = @options[:glyph_renderer]
        @image_frame = [@options[:image_frame].to_i, 0].max
        @cursor_blink_interval = positive_float(@options[:cursor_blink_interval], 0.5)
        @cursor_visible = true
        @last_cursor_tick = nil
        @frame = nil
        @rendered_at = nil
      end

      def activate(terminal)
        super
        measure_cell
        render
      end

      def render(start_row: 0, end_row: nil)
        ensure_active!

        end_row = @terminal.rows - 1 if end_row.nil?
        @frame = empty_frame
        draw_rows(start_row.to_i, end_row.to_i)
        draw_images if @draw_images
        draw_cursor if cursor_drawn?
        @rendered_at = Time.now
        emit(:raster, raster_payload)
        emit_terminal(:raster_render, raster_payload)
        @frame
      end

      def pixel_at(x, y)
        ensure_frame!

        row = @frame[:pixels][y.to_i]
        row && row[x.to_i]
      end

      def to_ppm
        ensure_frame!

        body = @frame[:pixels].flat_map do |row|
          row.map { |red, green, blue, _alpha| "#{red} #{green} #{blue}" }
        end
        (["P3", "#{@frame[:width]} #{@frame[:height]}", "255"] + body).join("\n")
      end

      def advance_cursor_blink(now: Time.now)
        return @cursor_visible unless @terminal&.options&.cursor_blink

        timestamp = now.to_f
        @last_cursor_tick ||= timestamp
        return @cursor_visible if (timestamp - @last_cursor_tick) < @cursor_blink_interval

        @last_cursor_tick = timestamp
        @cursor_visible = !@cursor_visible
        render
        @cursor_visible
      end

      def set_cursor_visible(value)
        @cursor_visible = !!value
        render if @terminal
        @cursor_visible
      end

      def on_raster(&block)
        on(:raster, &block)
      end

      alias renderRaster render
      alias pixelAt pixel_at
      alias toPpm to_ppm
      alias advanceCursorBlink advance_cursor_blink
      alias setCursorVisible set_cursor_visible
      alias onRaster on_raster

      private

      def handle_render(payload)
        super
        data = normalize_render_payload(payload)
        render(start_row: data[:start], end_row: data[:end]) if active?
      end

      def handle_resize(payload)
        super
        render if active?
      end

      def measure_cell
        service = @terminal.internal.services.get(Services::CHAR_SIZE_SERVICE)
        if @options.key?(:cell_width) || @options.key?(:cell_height)
          service.measure(width: @cell_width, height: @cell_height)
        elsif !service.ready?
          service.estimate_from_options(@terminal.options)
        end
        measured = service.size
        @cell_width = positive_integer(measured[:width], @cell_width)
        @cell_height = positive_integer(measured[:height], @cell_height)
      end

      def empty_frame
        width = @terminal.cols * @cell_width
        height = @terminal.rows * @cell_height
        background = parse_color(@terminal.options.theme&.fetch(:background, nil) || RTerm::Theme::DEFAULTS[:background])
        {
          width: width,
          height: height,
          cell_width: @cell_width,
          cell_height: @cell_height,
          pixels: Array.new(height) { Array.new(width) { background.dup } },
          images: [],
          cursor: nil
        }
      end

      def draw_rows(start_row, end_row)
        buffer = @terminal.buffer.active
        viewport_start = buffer.y_disp
        (start_row..end_row).each do |visible_row|
          line = buffer.get_line(viewport_start + visible_row)
          next unless line

          (0...@terminal.cols).each do |col|
            cell = line.get_cell(col)
            draw_cell(cell, col, visible_row) if cell
          end
        end
      end

      def draw_cell(cell, col, row)
        colors = @terminal.cell_colors(cell)
        x = col * @cell_width
        y = row * @cell_height
        fill_rect(x, y, @cell_width, @cell_height, parse_color(colors[:background]))
        return unless @draw_text && cell.has_content? && cell.width.positive? && cell.char != " "

        draw_glyph(cell.char, x, y, parse_color(colors[:foreground]))
      end

      def draw_glyph(char, x, y, color)
        mask = glyph_mask(char)
        return draw_glyph_block(x, y, color) if mask.empty?

        cell_left = x + [@cell_width / 8, 1].max
        cell_top = y + [@cell_height / 8, 1].max
        pixel_width = [(@cell_width - 2) / mask.first.length, 1].max
        pixel_height = [(@cell_height - 2) / mask.length, 1].max
        mask.each_with_index do |line, row|
          line.chars.each_with_index do |bit, col|
            next unless bit == "1"

            fill_rect(cell_left + (col * pixel_width), cell_top + (row * pixel_height), pixel_width, pixel_height, color)
          end
        end
      end

      def glyph_mask(char)
        custom = @glyph_renderer.call(char, @cell_width, @cell_height) if @glyph_renderer.respond_to?(:call)
        return custom if custom.is_a?(Array)

        BASIC_GLYPHS[char] || BASIC_GLYPHS[char.to_s.upcase] || []
      end

      def draw_glyph_block(x, y, color)
        fill_rect(
          x + [@cell_width / 4, 1].max,
          y + [@cell_height / 4, 1].max,
          [@cell_width / 2, 1].max,
          [@cell_height / 2, 1].max,
          color
        )
      end

      def draw_cursor
        buffer = @terminal.buffer.active
        x = buffer.x * @cell_width
        y = buffer.y * @cell_height
        color = parse_color(RTerm::Theme::DEFAULTS[:cursor])
        fill_rect(x, y, @cell_width, @cell_height, color)
        @frame[:cursor] = { row: buffer.y, col: buffer.x, visible: true }
      end

      def draw_images
        viewport_start = @terminal.buffer.active.y_disp
        @terminal.images.each do |image|
          placement = image[:placement] || {}
          next unless placement[:buffer] == buffer_name

          row = placement[:row].to_i - viewport_start
          col = placement[:col].to_i
          next if row >= @terminal.rows || (row + image_rows(image)) <= 0

          decoded = decode_image(image)
          next unless decoded

          if decoded[:format] == :rgba
            compose_rgba_image(decoded, col * @cell_width, row * @cell_height, image)
          elsif decoded[:format] == :indexed_rgba
            compose_indexed_image(decoded, col * @cell_width, row * @cell_height, image)
          elsif decoded[:format] == :sampled
            compose_sampled_image_preview(decoded, col * @cell_width, row * @cell_height, image)
          elsif decoded[:format] == :binary
            compose_binary_image_preview(decoded, col * @cell_width, row * @cell_height, image)
          end
        end
      end

      def compose_rgba_image(decoded, x, y, source)
        source_width = [decoded[:width].to_i, 1].max
        source_height = [decoded[:height].to_i, 1].max
        target_width = [image_cols(source) * @cell_width, source_width].max
        target_height = [image_rows(source) * @cell_height, source_height].max
        pixels = rgba_pixels(decoded)

        target_height.times do |target_y|
          source_y = [(target_y * source_height / target_height), source_height - 1].min
          target_width.times do |target_x|
            source_x = [(target_x * source_width / target_width), source_width - 1].min
            color = pixels[source_y]&.[](source_x)
            set_pixel(x + target_x, y + target_y, color) if color
          end
        end

        @frame[:images] << {
          protocol: source[:protocol],
          format: decoded[:format],
          media_type: decoded[:media_type],
          name: decoded[:name],
          frame: selected_frame_index(decoded),
          frame_count: decoded[:frame_count],
          x: x,
          y: y,
          width: target_width,
          height: target_height
        }.compact
      end

      def rgba_pixels(decoded)
        frames = decoded[:frames]
        return decoded[:pixels] unless frames.is_a?(Array) && !frames.empty?

        frames[selected_frame_index(decoded)][:pixels]
      end

      def selected_frame_index(decoded)
        frames = decoded[:frames]
        return nil unless frames.is_a?(Array) && !frames.empty?

        [@image_frame, frames.length - 1].min
      end

      def compose_indexed_image(decoded, x, y, source)
        source_width = [decoded[:width].to_i, 1].max
        source_height = [decoded[:height].to_i, 1].max
        target_width = [image_cols(source) * @cell_width, source_width].max
        target_height = [image_rows(source) * @cell_height, source_height].max

        target_height.times do |target_y|
          source_y = [(target_y * source_height / target_height), source_height - 1].min
          target_width.times do |target_x|
            source_x = [(target_x * source_width / target_width), source_width - 1].min
            palette_index = decoded[:pixels][source_y]&.[](source_x)
            next if palette_index.nil?

            color = decoded[:palette][palette_index] || [0, 0, 0, 255]
            set_pixel(x + target_x, y + target_y, color)
          end
        end

        @frame[:images] << {
          protocol: source[:protocol],
          x: x,
          y: y,
          width: target_width,
          height: target_height
        }
      end

      def compose_binary_image_preview(decoded, x, y, source)
        target_width = [image_cols(source) * @cell_width, @cell_width].max
        target_height = [image_rows(source) * @cell_height, @cell_height].max
        color = preview_color(decoded[:bytes].to_s)
        fill_rect(x, y, target_width, target_height, color)
        outline_rect(x, y, target_width, target_height, [255, 255, 255, 180])
        @frame[:images] << {
          protocol: source[:protocol],
          format: decoded[:format],
          name: decoded[:name],
          byte_size: decoded[:byte_size],
          x: x,
          y: y,
          width: target_width,
          height: target_height
        }.compact
      end

      def compose_sampled_image_preview(decoded, x, y, source)
        target_width = [image_cols(source) * @cell_width, decoded[:width].to_i, @cell_width].max
        target_height = [image_rows(source) * @cell_height, decoded[:height].to_i, @cell_height].max
        target_height.times do |row|
          target_width.times do |col|
            red = (col * 255 / [target_width - 1, 1].max)
            green = (row * 255 / [target_height - 1, 1].max)
            blue = preview_color(decoded[:bytes].to_s)[2]
            set_pixel(x + col, y + row, [red, green, blue, 255])
          end
        end
        outline_rect(x, y, target_width, target_height, [255, 255, 255, 160])
        @frame[:images] << {
          protocol: source[:protocol],
          format: decoded[:format],
          media_type: decoded[:media_type],
          name: decoded[:name],
          byte_size: decoded[:byte_size],
          x: x,
          y: y,
          width: target_width,
          height: target_height
        }.compact
      end

      def decode_image(image)
        case image[:protocol]
        when :sixel
          Common::SixelDecoder.decode(image)
        when :iterm2
          Common::Iterm2Decoder.decode(image)
        else
          nil
        end
      end

      def image_cols(image)
        ((image[:occupancy] || {})[:cols] || 1).to_i
      end

      def image_rows(image)
        ((image[:occupancy] || {})[:rows] || 1).to_i
      end

      def cursor_drawn?
        @draw_cursor && @cursor_visible
      end

      def buffer_name
        active = @terminal.buffer.active
        active.equal?(@terminal.buffer.alt) ? :alt : :normal
      end

      def fill_rect(x, y, width, height, color)
        height.times do |row_offset|
          width.times do |col_offset|
            set_pixel(x + col_offset, y + row_offset, color)
          end
        end
      end

      def outline_rect(x, y, width, height, color)
        width.times do |col_offset|
          set_pixel(x + col_offset, y, color)
          set_pixel(x + col_offset, y + height - 1, color)
        end
        height.times do |row_offset|
          set_pixel(x, y + row_offset, color)
          set_pixel(x + width - 1, y + row_offset, color)
        end
      end

      def preview_color(bytes)
        checksum = bytes.bytes.sum
        [
          64 + (checksum % 128),
          64 + ((checksum / 3) % 128),
          64 + ((checksum / 7) % 128),
          220
        ]
      end

      def set_pixel(x, y, color)
        return if x.negative? || y.negative? || y >= @frame[:height] || x >= @frame[:width]

        alpha = color[3].to_i
        @frame[:pixels][y][x] = if alpha >= 255
          color.dup
        elsif alpha <= 0
          @frame[:pixels][y][x]
        else
          blend(@frame[:pixels][y][x], color)
        end
      end

      def blend(background, foreground)
        alpha = foreground[3] / 255.0
        [
          ((foreground[0] * alpha) + (background[0] * (1 - alpha))).round,
          ((foreground[1] * alpha) + (background[1] * (1 - alpha))).round,
          ((foreground[2] * alpha) + (background[2] * (1 - alpha))).round,
          255
        ]
      end

      def parse_color(value)
        text = value.to_s
        return [0, 0, 0, 0] if text == "transparent"
        return [0, 0, 0, 255] unless text.match?(/\A#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?\z/)

        alpha = text[7, 2]
        alpha = "ff" if alpha.to_s.empty?
        [text[1, 2], text[3, 2], text[5, 2], alpha].map { |part| part.to_i(16) }
      end

      def raster_payload
        {
          type: renderer_type,
          frame: @frame,
          rendered_at: @rendered_at
        }
      end

      def ensure_active!
        raise RuntimeError, "Raster renderer is not active" unless @terminal
      end

      def ensure_frame!
        render unless @frame
      end

      def positive_integer(value, fallback)
        number = value.to_i
        number.positive? ? number : fallback
      end

      def positive_float(value, fallback)
        number = value.to_f
        number.positive? ? number : fallback
      end
    end
  end
end
