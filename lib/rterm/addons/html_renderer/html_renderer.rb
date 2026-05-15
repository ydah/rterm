# frozen_string_literal: true

require_relative "../screen_renderer/screen_renderer"

module RTerm
  module Addon
    class HtmlRenderer < ScreenRenderer
      DEFAULT_CAPABILITIES = ScreenRenderer::DEFAULT_CAPABILITIES.merge(
        html: true,
        aria: true,
        css: true
      ).freeze
      RENDERER_TYPE = :html

      def initialize(options = {})
        super
        @class_name = @options.fetch(:class_name, "rterm-html")
      end

      def html(document: false, styles: true)
        ensure_screen!

        body = terminal_html(styles: styles)
        return body unless document

        <<~HTML.chomp
          <!doctype html>
          <html>
          <head>
          <meta charset="utf-8">
          <title>RTerm</title>
          </head>
          <body>
          #{body}
          </body>
          </html>
        HTML
      end

      def css
        [
          ".#{@class_name} { font-family: monospace; white-space: pre; }",
          ".#{@class_name} .rterm-row { height: 1lh; }",
          ".#{@class_name} .rterm-cell { display: inline-block; min-width: 1ch; }",
          ".#{@class_name} .rterm-live-region { position: absolute; left: -10000px; }"
        ].join("\n")
      end

      def aria_html
        tree = accessibility_tree
        rows = Array(tree[:children]).map do |row|
          %(<div role="row" aria-rowindex="#{row[:row].to_i + 1}">#{escape_html(row[:text])}</div>)
        end.join

        %(<div role="grid" aria-label="Terminal" aria-rowcount="#{tree[:rows]}" aria-colcount="#{tree[:cols]}">#{rows}</div>)
      end

      alias to_html html
      alias toHtml html
      alias ariaHtml aria_html

      private

      def terminal_html(styles:)
        attrs = {
          "class" => @class_name,
          "role" => "application",
          "data-cols" => @screen[:cols],
          "data-rows" => @screen[:rows_count],
          "data-cursor-row" => @screen[:cursor][:row],
          "data-cursor-col" => @screen[:cursor][:col]
        }
        style_tag = styles ? "<style>#{escape_html(css)}</style>" : ""
        live = live_region_html
        rows_html = rows.map { |row| row_html(row) }.join

        "#{style_tag}<div #{html_attrs(attrs)}>#{rows_html}#{live}</div>"
      end

      def row_html(row)
        attrs = {
          "class" => "rterm-row",
          "role" => "row",
          "aria-rowindex" => row[:row].to_i + 1,
          "data-row" => row[:row],
          "data-absolute-row" => row[:absolute_row],
          "data-wrapped" => row[:wrapped]
        }
        cells = row[:cells].map { |cell| cell_html(cell) }.join

        "<div #{html_attrs(attrs)}>#{cells}</div>"
      end

      def cell_html(cell)
        attrs = {
          "class" => cell_class(cell),
          "role" => "gridcell",
          "aria-colindex" => cell[:col].to_i + 1,
          "data-col" => cell[:col],
          "data-width" => cell[:width],
          "style" => cell_style(cell)
        }
        text = cell[:char].to_s.empty? ? " " : cell[:char].to_s

        "<span #{html_attrs(attrs)}>#{escape_html(text)}</span>"
      end

      def cell_class(cell)
        classes = ["rterm-cell"]
        cell[:attributes].each { |name, value| classes << "is-#{name}" if value }
        classes.join(" ")
      end

      def cell_style(cell)
        colors = cell[:colors] || {}
        [
          css_decl("color", colors[:foreground]),
          css_decl("background-color", colors[:background])
        ].compact.join(" ")
      end

      def live_region_html
        region = accessibility_tree[:live_region]
        return "" unless region

        text = region[:text_content].to_s
        %(<div class="rterm-live-region" role="status" aria-live="polite">#{escape_html(text)}</div>)
      end

      def html_attrs(attrs)
        attrs.filter_map do |name, value|
          next if value.nil? || value == ""

          %(#{name}="#{escape_html(value)}")
        end.join(" ")
      end

      def css_decl(name, value)
        return nil if value.nil? || value == ""

        "#{name}: #{value};"
      end

      def escape_html(value)
        value.to_s
             .gsub("&", "&amp;")
             .gsub("<", "&lt;")
             .gsub(">", "&gt;")
             .gsub('"', "&quot;")
      end
    end
  end
end
