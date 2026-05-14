# frozen_string_literal: true

require_relative "../renderer_lifecycle"

module RTerm
  module Addon
    class ScreenRenderer < RendererLifecycle
      DEFAULT_CAPABILITIES = {
        dom_tree: true,
        text_snapshot: true,
        style_snapshot: true,
        accessibility_tree: true
      }.freeze
      RENDERER_TYPE = :screen

      attr_reader :screen, :accessibility_tree, :rendered_at

      def initialize(options = {})
        super
        @screen = nil
        @accessibility_tree = nil
        @rendered_at = nil
        @trim_right = @options.fetch(:trim_right, false)
      end

      def activate(terminal)
        super
        attach_host(default_host) unless host
        render
      end

      def render(start_row: 0, end_row: nil)
        ensure_active!

        end_row = @terminal.rows - 1 if end_row.nil?
        @screen = build_screen(start_row.to_i, end_row.to_i)
        @accessibility_tree = @terminal.accessibility_tree
        @rendered_at = Time.now
        emit(:screen, screen_payload)
        emit_terminal(:screen_render, screen_payload)
        @screen
      end

      def text
        ensure_screen!

        @screen[:rows].map { |row| row[:text] }.join("\n")
      end

      def elements
        ensure_screen!

        @screen[:element]
      end

      def rows
        ensure_screen!

        deep_dup(@screen[:rows])
      end

      def accessibility_tree
        @terminal ? @terminal.accessibility_tree : deep_dup(@accessibility_tree)
      end

      def on_screen(&block)
        on(:screen, &block)
      end

      alias renderScreen render
      alias accessibilityTree accessibility_tree
      alias onScreen on_screen

      private

      def handle_render(payload)
        super
        data = normalize_render_payload(payload)
        render(start_row: data[:start], end_row: data[:end]) if active?
      end

      def build_screen(start_row, end_row)
        buffer = @terminal.buffer.active
        viewport_start = buffer.y_disp
        rows = []
        root = root_element
        root.children.clear
        root.dataset["cols"] = @terminal.cols.to_s
        root.dataset["rows"] = @terminal.rows.to_s

        (start_row..end_row).each do |visible_row|
          absolute_row = viewport_start + visible_row
          line = buffer.get_line(absolute_row)
          row = row_snapshot(line, visible_row, absolute_row)
          rows << row
          root.append_child(row[:element])
        end

        {
          cols: @terminal.cols,
          rows_count: @terminal.rows,
          viewport_start: viewport_start,
          element: root,
          rows: rows,
          cursor: {
            row: buffer.y,
            col: buffer.x,
            absolute_row: buffer.y_base + buffer.y
          }
        }
      end

      def row_snapshot(line, visible_row, absolute_row)
        element = RTerm::Terminal::HostElement.new(tag_name: "div", class_name: "rterm-row")
        element.dataset["row"] = visible_row.to_s
        element.dataset["absoluteRow"] = absolute_row.to_s
        cells = cell_snapshots(line, visible_row, element)
        text = line ? line.to_string(trim_right: @trim_right) : ""
        element.text_content = text

        {
          row: visible_row,
          absolute_row: absolute_row,
          text: text,
          wrapped: line&.is_wrapped || false,
          element: element,
          cells: cells
        }
      end

      def cell_snapshots(line, visible_row, row_element)
        (0...@terminal.cols).filter_map do |col|
          cell = line&.get_cell(col)
          next unless cell

          snapshot = cell_snapshot(cell, visible_row, col)
          row_element.append_child(snapshot[:element])
          snapshot
        end
      end

      def cell_snapshot(cell, row, col)
        element = RTerm::Terminal::HostElement.new(tag_name: "span", class_name: "rterm-cell")
        element.dataset["row"] = row.to_s
        element.dataset["col"] = col.to_s
        element.dataset["width"] = cell.width.to_s
        element.text_content = cell.has_content? ? cell.char : " "
        colors = @terminal.cell_colors(cell)
        element.style["color"] = colors[:foreground].to_s if colors[:foreground]
        element.style["backgroundColor"] = colors[:background].to_s if colors[:background]

        {
          row: row,
          col: col,
          char: cell.char,
          width: cell.width,
          colors: colors,
          attributes: cell_attributes(cell),
          link: cell.link,
          element: element
        }
      end

      def cell_attributes(cell)
        {
          bold: cell.bold?,
          italic: cell.italic?,
          underline: cell.underline?,
          blink: cell.blink?,
          inverse: cell.inverse?,
          invisible: cell.invisible?,
          strikethrough: cell.strikethrough?,
          dim: cell.dim?,
          overline: cell.overline?
        }
      end

      def root_element
        return host if host.respond_to?(:children)

        default_host
      end

      def default_host
        RTerm::Terminal::HostElement.new(tag_name: "div", class_name: "rterm-screen")
      end

      def screen_payload
        {
          type: renderer_type,
          screen: @screen,
          accessibility_tree: @accessibility_tree,
          rendered_at: @rendered_at
        }
      end

      def ensure_active!
        raise RuntimeError, "Screen renderer is not active" unless @terminal
      end

      def ensure_screen!
        render unless @screen
      end
    end
  end
end
