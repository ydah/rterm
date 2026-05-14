# frozen_string_literal: true

require_relative "../renderer_lifecycle"
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

      attr_reader :frame, :cursor_visible, :rendered_at

      def initialize(options = {})
        super
        @cell_width = positive_integer(@options[:cell_width], 8)
        @cell_height = positive_integer(@options[:cell_height], 16)
        @draw_text = @options.fetch(:draw_text, true) != false
        @draw_images = @options.fetch(:draw_images, true) != false
        @draw_cursor = @options.fetch(:draw_cursor, true) != false
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

        draw_glyph_block(x, y, parse_color(colors[:foreground]))
      end

      def draw_glyph_block(x, y, color)
        margin_x = [@cell_width / 4, 1].max
        margin_y = [@cell_height / 4, 1].max
        fill_rect(
          x + margin_x,
          y + margin_y,
          [@cell_width - (margin_x * 2), 1].max,
          [@cell_height - (margin_y * 2), 1].max,
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
          next unless decoded && decoded[:format] == :indexed_rgba

          compose_indexed_image(decoded, col * @cell_width, row * @cell_height, image)
        end
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

      def decode_image(image)
        case image[:protocol]
        when :sixel
          Common::SixelDecoder.decode(image)
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
