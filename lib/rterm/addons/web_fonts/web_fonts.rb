# frozen_string_literal: true

require_relative "../base"

module RTerm
  module Addon
    class WebFonts < Base
      include Common::EventEmitter

      CSS_DESCRIPTOR_NAMES = {
        source: "src",
        style: "font-style",
        weight: "font-weight",
        stretch: "font-stretch",
        display: "font-display",
        unicode_range: "unicode-range",
        feature_settings: "font-feature-settings",
        variation_settings: "font-variation-settings"
      }.freeze

      KEY_PARTS = %i[family stretch style unicode_range weight].freeze

      attr_reader :initial_relayout

      def initialize(initial_relayout = true, fonts: nil)
        if initial_relayout.respond_to?(:to_h) && !initial_relayout.is_a?(String)
          options = initial_relayout.to_h
          initial_relayout = option_value(options, :initial_relayout, :initialRelayout, default: true)
          fonts = option_value(options, :fonts, "fonts", default: fonts)
        end

        @initial_relayout = !!initial_relayout
        @faces = []
        @loaded_keys = {}
        font_list(fonts).each { |font| register_font(font) } if fonts
      end

      def activate(terminal)
        super
        relayout if @initial_relayout
      end

      def dispose
        @terminal = nil
        super
      end

      def register_font(family_or_face = nil, source = nil, **descriptors)
        if family_or_face.nil? && !descriptors.empty?
          family_or_face = descriptors
          descriptors = {}
        end

        face = normalize_face(family_or_face, source, descriptors)
        key = face_key(face)
        existing = @faces.find { |item| face_key(item) == key }
        return deep_dup(existing) if existing

        @faces << face.merge(status: :registered)
        emit(:register, deep_dup(@faces.last))
        deep_dup(@faces.last)
      end

      def load_fonts(fonts = nil)
        targets = font_targets(fonts)

        targets.map do |face|
          key = face_key(face)
          @loaded_keys[key] = true
          stored = @faces.find { |item| face_key(item) == key }
          stored[:status] = :loaded if stored
          loaded = deep_dup(stored || face.merge(status: :loaded))
          emit(:load, loaded)
          @terminal&.internal&.emit(:font_load, loaded)
          loaded
        end
      end

      def relayout
        return false unless @terminal

        font_family = @terminal.get_option(:font_family).to_s
        requested_families = split_family(font_family)
        registered = families
        dirty = requested_families.select { |family| registered.include?(family) }
        return false if dirty.empty?

        loaded = load_fonts(dirty)
        clean = requested_families.reject { |family| dirty.include?(family) }
        fallback = clean.empty? ? "monospace" : create_family(clean)

        @terminal.set_option(:font_family, fallback)
        @terminal.set_option(:font_family, font_family)

        payload = {
          font_family: font_family,
          fontFamily: font_family,
          fallback: fallback,
          loaded: loaded
        }
        emit(:relayout, payload)
        @terminal.internal.emit(:font_relayout, payload)
        true
      end

      def fonts
        deep_dup(@faces)
      end

      def loaded_fonts
        @faces.select { |face| @loaded_keys[face_key(face)] }.map { |face| deep_dup(face) }
      end

      def families
        @faces.map { |face| face[:family] }.uniq
      end

      def loaded_families
        loaded_fonts.map { |face| face[:family] }.uniq
      end

      def loaded?(font = nil)
        return @faces.any? && @faces.all? { |face| @loaded_keys[face_key(face)] } if font.nil?

        if font.respond_to?(:to_h) && !font.is_a?(String)
          return @loaded_keys[face_key(normalize_face(font, nil, {}))]
        end

        loaded_families.include?(unquote_family(font.to_s))
      end

      def font_face_css
        @faces.map { |face| font_face_rule(face) }.join("\n")
      end

      def resolve_font_family(value = nil, fallback: "monospace")
        requested = split_family(value || @terminal&.get_option(:font_family))
        requested = [fallback] if requested.empty?
        registered = families
        loaded = loaded_families
        selected = requested.find { |family| loaded.include?(family) } ||
          requested.find { |family| registered.include?(family) } ||
          requested.first ||
          fallback
        family = create_family((requested | [fallback]))

        {
          requested: requested,
          registered: registered,
          loaded: loaded,
          selected: selected,
          fallback: fallback,
          font_family: family,
          fontFamily: family
        }
      end

      def measure_cell(font_size: nil, line_height: nil, letter_spacing: nil)
        raise RuntimeError, "WebFonts addon is not active" unless @terminal

        options = @terminal.options.to_h
        size = @terminal.internal.services
                        .get(Services::CHAR_SIZE_SERVICE)
                        .estimate(
                          font_size: font_size || options[:font_size],
                          line_height: line_height || options[:line_height],
                          letter_spacing: letter_spacing || options[:letter_spacing]
                        )
        payload = size.merge(font: resolve_font_family)
        emit(:measure, payload)
        @terminal.internal.emit(:font_measure, payload)
        payload
      end

      def on_load(&block)
        on(:load, &block)
      end

      def on_relayout(&block)
        on(:relayout, &block)
      end

      def on_measure(&block)
        on(:measure, &block)
      end

      alias initialRelayout initial_relayout
      alias registerFont register_font
      alias loadFonts load_fonts
      alias loadedFonts loaded_fonts
      alias loadedFamilies loaded_families
      alias fontFaceCss font_face_css
      alias resolveFontFamily resolve_font_family
      alias measureCell measure_cell
      alias onLoad on_load
      alias onRelayout on_relayout
      alias onMeasure on_measure

      private

      def font_targets(fonts)
        return @faces if fonts.nil?

        font_list(fonts).flat_map do |font|
          if font.respond_to?(:to_h) && !font.is_a?(String)
            [register_font(font)]
          else
            family = unquote_family(font.to_s)
            matches = @faces.select { |face| face[:family] == family }
            raise ArgumentError, %(font family "#{family}" is not registered) if matches.empty?

            matches
          end
        end.uniq { |face| face_key(face) }
      end

      def normalize_face(family_or_face, source, descriptors)
        values = if family_or_face.respond_to?(:to_h) && !family_or_face.is_a?(String)
          symbolize_face(family_or_face.to_h)
        else
          { family: family_or_face, source: source }
        end

        values = values.merge(symbolize_face(descriptors))
        values[:source] = source if source && values[:source].nil?
        values[:family] = unquote_family(values[:family].to_s)
        values[:style] ||= "normal"
        values[:weight] ||= "normal"
        values[:stretch] ||= "normal"
        values[:unicode_range] ||= "U+0-10FFFF"

        raise ArgumentError, "font family is required" if values[:family].empty?

        values.compact
      end

      def font_list(value)
        return [] if value.nil?
        return value if value.is_a?(Array)

        [value]
      end

      def symbolize_face(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[normalize_key(key)] = value
        end
      end

      def normalize_key(key)
        case key.to_s
        when "fontFamily", "font_family"
          :family
        when "src"
          :source
        when "fontStyle", "font_style"
          :style
        when "fontWeight", "font_weight"
          :weight
        when "fontStretch", "font_stretch"
          :stretch
        when "fontDisplay", "font_display"
          :display
        when "unicodeRange", "unicode-range"
          :unicode_range
        when "fontFeatureSettings", "font_feature_settings"
          :feature_settings
        when "fontVariationSettings", "font_variation_settings"
          :variation_settings
        else
          key.to_s.tr("-", "_").to_sym
        end
      end

      def face_key(face)
        KEY_PARTS.map { |name| face[name].to_s }.join("\0")
      end

      def font_face_rule(face)
        lines = ["@font-face {"]
        lines << "  font-family: #{quote_family(face[:family])};"
        CSS_DESCRIPTOR_NAMES.each do |key, css_name|
          next if key == :source || face[key].nil?

          lines << "  #{css_name}: #{face[key]};"
        end
        lines << "  src: #{face[:source]};" if face[:source]
        lines << "}"
        lines.join("\n")
      end

      def split_family(value)
        families = []
        current = +""
        quote = nil

        value.to_s.each_char do |char|
          if quote
            quote = nil if char == quote
            current << char
            next
          end

          if char == "'" || char == '"'
            quote = char
            current << char
          elsif char == ","
            families << unquote_family(current.strip)
            current = +""
          else
            current << char
          end
        end

        families << unquote_family(current.strip)
        families.reject(&:empty?)
      end

      def create_family(families)
        families.map { |family| quote_family(family) }.join(", ")
      end

      def quote_family(family)
        text = unquote_family(family.to_s)
        return text if text.match?(/\A(?!-?\d|--)[-_a-zA-Z0-9]+\z/)

        %("#{text.gsub('"', '\"')}")
      end

      def unquote_family(family)
        text = family.to_s.strip
        return text[1...-1] if text.length >= 2 && ((text.start_with?('"') && text.end_with?('"')) || (text.start_with?("'") && text.end_with?("'")))

        text
      end

      def option_value(options, *keys, default:)
        keys.each do |key|
          return options[key] if options.key?(key)
        end
        default
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
