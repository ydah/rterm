# frozen_string_literal: true

require_relative "headless/headless_terminal"
require_relative "terminal/input_surface"

module RTerm
  # Main public API for the terminal emulator.
  # Wraps HeadlessTerminal with a user-friendly interface.
  class Terminal
    URL_SELECTION_REGEX = %r{(?<![\w@])https?://[^\s<>\[\]{}|\\^`"']+}i
    URL_TRAILING_PUNCTUATION = ".,;:!?"
    LOCALIZABLE_STRINGS = {
      "promptLabel" => "Terminal input",
      "tooMuchOutput" => "Terminal output is too large to announce"
    }.freeze

    class Marker
      include Common::EventEmitter

      def initialize(id, line)
        @id = id
        @line = line
        @disposed = false
      end

      attr_reader :id
      attr_accessor :line

      def dispose
        return if @disposed

        @disposed = true
        @line = -1
        emit(:dispose, self)
        true
      end

      def on_dispose(&block)
        return unless block

        on(:dispose, &block)
      end

      def disposed?
        @disposed
      end

      alias isDisposed disposed?
      alias is_disposed? disposed?
      alias onDispose on_dispose
    end

    class Decoration
      include Common::EventEmitter

      class Element
        attr_accessor :class_name, :text_content
        attr_reader :attributes, :dataset, :style

        def initialize(class_name: nil)
          @class_name = class_name
          @text_content = ""
          @attributes = {}
          @dataset = {}
          @style = {}
        end

        def tag_name
          "div"
        end

        def set_attribute(name, value)
          @attributes[name.to_s] = value
        end

        def get_attribute(name)
          @attributes[name.to_s]
        end

        def remove_attribute(name)
          @attributes.delete(name.to_s)
        end

        def to_h
          {
            tag_name: tag_name,
            class_name: @class_name,
            text_content: @text_content,
            attributes: @attributes.dup,
            dataset: @dataset.dup,
            style: @style.dup
          }
        end

        alias className class_name
        alias className= class_name=
        alias textContent text_content
        alias textContent= text_content=
        alias setAttribute set_attribute
        alias getAttribute get_attribute
        alias removeAttribute remove_attribute
      end

      def initialize(marker, options = {})
        @marker = marker
        @options = normalize_options(options || {})
        @public_options = build_public_options(@options)
        @element = nil
        @render_state = nil
        @disposed = false
      end

      attr_reader :element, :marker

      def render(viewport_start:, viewport_end:, cols:)
        return nil if @disposed || @marker.disposed?

        @render_state = build_render_state(
          viewport_start: viewport_start,
          viewport_end: viewport_end,
          cols: cols
        )
        update_element(@render_state)
        emit(:render, @element)
        @element
      end

      def render_state
        deep_dup(@render_state)
      end

      def element
        @element
      end

      def disposed?
        @disposed
      end

      alias isDisposed disposed?
      alias is_disposed? disposed?

      def dispose
        return if @disposed

        @disposed = true
        @element&.dataset&.[]=("disposed", "true")
        emit(:dispose)
        true
      end

      def on_render(&block)
        on(:render, &block)
      end

      def on_render_event(&block)
        on_render(&block)
      end

      def on_dispose(&block)
        on(:dispose, &block)
      end

      def options
        deep_dup(@public_options)
      end

      private

      def build_render_state(viewport_start:, viewport_end:, cols:)
        width = [@options[:width].to_i, 1].max
        height = [@options[:height].to_i, 1].max
        x = [@options[:x].to_i, 0].max
        anchor = normalize_anchor(@options[:anchor])
        column = anchor == :right ? cols.to_i - width - x : x
        column = [[column, 0].max, [cols.to_i - 1, 0].max].min
        row = @marker.line.to_i - viewport_start.to_i
        visible = @marker.line.to_i.between?(viewport_start.to_i, viewport_end.to_i)

        {
          marker_id: @marker.id,
          line: @marker.line,
          row: row,
          x: column,
          width: width,
          height: height,
          anchor: anchor,
          layer: normalize_layer(@options[:layer]),
          visible: visible,
          overviewRulerOptions: deep_dup(@public_options[:overviewRulerOptions]),
          backgroundColor: @options[:backgroundColor],
          foregroundColor: @options[:foregroundColor]
        }.compact
      end

      def update_element(state)
        @element ||= Element.new(class_name: @options[:className])
        @element.class_name = @options[:className] if @options.key?(:className)
        @element.dataset["markerId"] = state[:marker_id].to_s
        @element.dataset["line"] = state[:line].to_s
        @element.dataset["row"] = state[:row].to_s
        @element.dataset["x"] = state[:x].to_s
        @element.dataset["visible"] = state[:visible].to_s
        @element.style["display"] = state[:visible] ? "" : "none"
        @element.style["left"] = "#{state[:x]}cell"
        @element.style["top"] = "#{state[:row]}cell"
        @element.style["width"] = "#{state[:width]}cell"
        @element.style["height"] = "#{state[:height]}cell"
        @element.style["zIndex"] = state[:layer] == :top ? "1" : "0"
        @element.style["backgroundColor"] = state[:backgroundColor] if state[:backgroundColor]
        @element.style["color"] = state[:foregroundColor] if state[:foregroundColor]
      end

      def build_public_options(options)
        result = {}
        result[:overviewRulerOptions] = deep_dup(options[:overviewRulerOptions]) if options.key?(:overviewRulerOptions)
        result
      end

      def normalize_options(options)
        options.to_h.each_with_object({}) do |(key, value), result|
          result[normalize_option_key(key)] = normalize_option_value(key, value)
        end
      end

      def normalize_option_key(key)
        case key.to_s
        when "overviewRulerOptions", "overview_ruler_options"
          :overviewRulerOptions
        when "backgroundColor", "background_color"
          :backgroundColor
        when "foregroundColor", "foreground_color"
          :foregroundColor
        when "className", "class_name"
          :className
        else
          key.to_s.tr("-", "_").to_sym
        end
      end

      def normalize_option_value(key, value)
        normalized_key = normalize_option_key(key)
        case normalized_key
        when :overviewRulerOptions
          normalize_overview_ruler_options(value)
        when :anchor
          normalize_anchor(value)
        when :layer
          normalize_layer(value)
        else
          deep_dup(value)
        end
      end

      def normalize_overview_ruler_options(value)
        return nil unless value.respond_to?(:to_h)

        value.to_h.each_with_object({}) do |(key, item), result|
          result[normalize_overview_ruler_key(key)] = deep_dup(item)
        end
      end

      def normalize_overview_ruler_key(key)
        case key.to_s
        when "position"
          :position
        when "color"
          :color
        else
          key.to_s.tr("-", "_").to_sym
        end
      end

      def normalize_anchor(value)
        anchor = value.to_s.empty? ? "left" : value.to_s
        anchor == "right" ? :right : :left
      end

      def normalize_layer(value)
        layer = value.to_s.empty? ? "bottom" : value.to_s
        layer == "top" ? :top : :bottom
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

      alias onRender on_render
      alias onRenderEvent on_render_event
      alias onDispose on_dispose
    end

    # @param options [Hash] terminal options
    # @option options [Integer] :cols (80) number of columns
    # @option options [Integer] :rows (24) number of rows
    # @option options [Integer] :scrollback (1000) scrollback buffer size
    def initialize(options = {})
      @terminal = Headless::HeadlessTerminal.new(options)
      @disposed = false
      @addons = []
      @selection = nil
      @container = nil
      @textarea = nil
      @composition = { active: false, data: "" }
      @custom_key_event_handler = nil
      @custom_wheel_event_handler = nil
      @custom_mouse_event_handler = nil
      @custom_context_menu_event_handler = nil
      @focused = false
      @markers = []
      @next_marker_id = 1
      @decorations = []
      @link_matchers = {}
      @next_link_matcher_id = 1
      @character_joiners = {}
      @next_character_joiner_id = 1
      @last_scroll_position = @terminal.buffer_set.active.y_disp
      @buffer_namespace = BufferNamespace.new(@terminal.buffer_set)

      @terminal.on(:scroll) do |position|
        on_terminal_scroll(position)
      end

      @terminal.on(:render) do |payload|
        render_decorations(payload)
      end

      @terminal.buffer_set.on(:buffer_change) do |payload|
        @buffer_namespace&.emit(:buffer_change, payload)
      end
    end

    # @return [Integer] number of columns
    def cols
      @terminal.cols
    end

    # @return [Integer] number of rows
    def rows
      @terminal.rows
    end

    # DOM-like container.
    def element
      @container
    end

    # Hidden textarea element.
    def textarea
      @textarea
    end

    # Localizable strings.
    # @return [Hash]
    def strings
      LOCALIZABLE_STRINGS.dup
    end

    # --- Data I/O ---

    # Writes data to the terminal (as if received from PTY).
    # @param data [String] the data to write
    # @param callback [Proc, nil] optional callback
    def write(data, callback = nil, &block)
      callback = block || callback
      @terminal.write(normalize_write_data(data))
      callback.call(nil) if callback
    end

    # Writes data followed by a carriage return and newline.
    # @param data [String] the data to write
    # @param callback [Proc, nil] optional callback
    def writeln(data, callback = nil, &block)
      callback = block || callback
      @terminal.writeln(normalize_write_data(data))
      callback.call(nil) if callback
    end

    # Registers a character joiner and returns its identifier.
    #
    # The joiner callback is stored for public API behavior but currently
    # is not used by the headless rendering path.
    #
    # @return [Integer]
    def register_character_joiner(&block)
      raise ArgumentError, "A character joiner block is required" unless block

      id = @next_character_joiner_id
      @next_character_joiner_id += 1
      @character_joiners[id] = block
      id
    end

    # CamelCase alias.
    def registerCharacterJoiner(&block)
      register_character_joiner(&block)
    end

    # Removes a previously registered character joiner by id.
    #
    # @param id [Integer]
    # @return [Boolean]
    def deregister_character_joiner(id)
      key = id.to_i
      existed = @character_joiners.key?(key)
      @character_joiners.delete(key)
      existed
    end

    # CamelCase alias.
    def deregisterCharacterJoiner(id)
      deregister_character_joiner(id)
    end

    # Simulates user input (sends data event for PTY forwarding).
    # @param data [String] the input data
    def input(data, was_user_input = true, **kwargs)
      was_user_input = normalize_was_user_input(was_user_input, kwargs)
      return if options.disable_stdin

      payload = data.to_s
      if was_user_input
        scroll_to_bottom if options.scroll_on_user_input
        clear_selection
      end

      @textarea&.set_value(payload)
      @terminal.emit(:textarea_input, input_surface_payload(payload, was_user_input: was_user_input)) if @textarea
      @terminal.emit(:data, payload)
      payload
    end

    # Simulates binary user input for protocols that bypass UTF-8 text paths.
    # @param data [String] binary input data
    # @return [String, nil]
    def binary(data)
      return if options.disable_stdin

      payload = data.to_s.b
      scroll_to_bottom if options.scroll_on_user_input
      @terminal.emit(:binary, payload)
      payload
    end

    # Simulates paste input, honoring bracketed paste mode when enabled.
    # @param data [String] pasted text
    # @return [String, nil] emitted payload
    def paste(data)
      text = data.to_s
      payload = text
      payload = "\e[200~#{payload}\e[201~" if modes[:bracketed_paste_mode]
      result = input(payload)
      @textarea&.set_value(text) if result
      result
    end

    def composition_start(data = nil)
      update_composition(data.to_s, active: true)
      payload = composition_payload(:composition_start, @composition[:data])
      @terminal.emit(:composition_start, payload)
      payload
    end

    def composition_update(data)
      update_composition(data.to_s, active: true)
      payload = composition_payload(:composition_update, @composition[:data])
      @terminal.emit(:composition_update, payload)
      payload
    end

    def composition_end(data = nil, commit: true)
      text = data.nil? ? @composition[:data].to_s : data.to_s
      update_composition(text, active: false)
      payload = composition_payload(:composition_end, text, committed: commit)
      @terminal.emit(:composition_end, payload)
      input(text) if commit && !text.empty?
      payload
    end

    def composition_state
      @composition.dup
    end

    alias compositionStart composition_start
    alias compositionUpdate composition_update
    alias compositionEnd composition_end
    alias compositionState composition_state

    # Encodes and emits a high-level key event as terminal input.
    # @param key [Symbol, String]
    # @param modifiers [Array<Symbol>]
    # @param text [String, nil]
    # @return [String, nil]
    def key_event(key, modifiers: [], text: nil)
      modifiers = Array(modifiers)
      payload = key_event_payload(key, modifiers, text)
      return nil if @custom_key_event_handler&.call(payload) == false

      encoded = Common::KeyEncoder.new(modes).encode(key, modifiers: key_modifiers(modifiers), text: text)
      @terminal.emit(:key, payload)
      input(encoded) if encoded
    end

    # CamelCase alias.
    # @param key [Symbol, String]
    # @param modifiers [Array<Symbol>]
    # @param text [String, nil]
    # @return [String, nil]
    def attachCustomKeyEventHandler(&block)
      attach_custom_key_event_handler(&block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def attachCustomWheelEventHandler(&block)
      attach_custom_wheel_event_handler(&block)
    end

    # CamelCase alias.
    # @param key [Symbol, String]
    # @param modifiers [Array<Symbol>]
    # @param text [String, nil]
    # @return [String, nil]
    def onKey(&block)
      on_key(&block)
    end

    # CamelCase alias.
    # @param key [Symbol, String]
    # @param modifiers [Array<Symbol>]
    # @param text [String, nil]
    # @return [String, nil]
    def onData(&block)
      on_data(&block)
    end

    def onOpen(&block)
      on_open(&block)
    end

    def onTextareaInput(&block)
      on_textarea_input(&block)
    end

    def onTextAreaInput(&block)
      on_textarea_input(&block)
    end

    def onCompositionStart(&block)
      on_composition_start(&block)
    end

    def onCompositionUpdate(&block)
      on_composition_update(&block)
    end

    def onCompositionEnd(&block)
      on_composition_end(&block)
    end

    # CamelCase alias.
    # @param key [Symbol, String]
    # @param modifiers [Array<Symbol>]
    # @param text [String, nil]
    # @return [String, nil]
    def onBinary(&block)
      on_binary(&block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onBell(&block)
      on_bell(&block)
    end

    # CamelCase alias.
    # @return [Common::Disposable]
    def onScroll(&block)
      on_scroll(&block)
    end

    # CamelCase alias.
    # @return [Common::Disposable]
    def onResize(&block)
      on_resize(&block)
    end

    # CamelCase alias.
    # @return [Common::Disposable]
    def onSelectionChange(&block)
      on_selection_change(&block)
    end

    # CamelCase alias.
    # @return [Common::Disposable]
    def onTitleChange(&block)
      on_title_change(&block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onContextMenu(&block)
      on_context_menu(&block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onRender(&block)
      on(:render, &block)
    end

    # CamelCase alias.
    # @param line [Integer, nil] line offset from the cursor, default is the cursor line
    # @return [Marker, nil]
    def registerMarker(line = nil)
      register_marker(line)
    end

    # Marker API.
    #
    # @param line [Integer, nil] line offset from the cursor, default is the cursor line
    # @yield [Marker] called when marker is disposed
    # @return [Marker, nil]
    def add_marker(line = nil)
      marker = register_marker(line)
      return marker unless marker

      if block_given?
        marker.on_dispose do |disposed_marker|
          yield(disposed_marker)
        end
      end

      marker
    end

    # CamelCase alias.
    # @param line [Integer, nil] line offset from the cursor, default is the cursor line
    # @yield [Marker] called when marker is disposed
    # @return [Marker, nil]
    def addMarker(line = nil, &block)
      add_marker(line, &block)
    end

    # Registers link providers.
    # The WebLinks addon is loaded on demand.
    def register_link_provider(provider = nil, &block)
      require_relative "addons/web_links/web_links" unless defined?(RTerm::Addon::WebLinks)
      web_links_addon.register_link_provider(provider, &block)
    end

    # CamelCase alias.
    def registerLinkProvider(provider = nil, &block)
      register_link_provider(provider, &block)
    end

    # Registers a link matcher callback.
    def register_link_matcher(matcher, handler = nil, options = nil)
      require_relative "addons/web_links/web_links" unless defined?(RTerm::Addon::WebLinks)

      matcher = Regexp.new(matcher) unless matcher.is_a?(Regexp)
      normalized = normalize_link_matcher_options(options)
      id = @next_link_matcher_id
      @next_link_matcher_id += 1

      provider = lambda do |text, row|
        scan_link_matches(text, matcher, handler, normalized, row)
      end

      @link_matchers[id] = web_links_addon.register_link_provider(provider)
      id
    end

    # CamelCase alias.
    def registerLinkMatcher(matcher, handler = nil, options = nil)
      register_link_matcher(matcher, handler, options)
    end

    # Remove a previously registered link matcher.
    # @param id [Integer]
    # @return [Boolean]
    def deregister_link_matcher(id)
      disposable = @link_matchers.delete(id.to_i)
      return false unless disposable

      disposable.dispose
      true
    end

    # CamelCase alias.
    def deregisterLinkMatcher(id)
      deregister_link_matcher(id)
    end

    # Registers marker decorations.
    def register_decoration(marker_or_options = nil, options = nil)
      normalized_options = {}
      marker = nil

      if marker_or_options.is_a?(Marker)
        marker = marker_or_options
        normalized_options = options.to_h if options
      else
        normalized_options = marker_or_options.to_h if marker_or_options.respond_to?(:to_h)
        marker = normalized_options.delete(:marker) || normalized_options.delete("marker")
      end

      marker ||= register_marker
      return nil unless marker

      decoration = Decoration.new(marker, normalized_options)
      @decorations << decoration
      decoration.on_dispose { @decorations.delete(decoration) }
      marker.on_dispose { decoration.dispose unless decoration.disposed? }
      decoration
    end

    # CamelCase alias.
    def registerDecoration(marker_or_options = nil, options = nil)
      register_decoration(marker_or_options, options)
    end

    # CamelCase alias.
    # @param line [Integer, nil] line offset from the cursor, default is the cursor line
    # @return [Marker, nil]
    def register_marker(line = nil)
      buffer = @terminal.buffer_set.active
      return nil if buffer.equal?(@terminal.buffer_set.alt)

      @last_scroll_position = buffer.y_disp
      offset = line.nil? ? 0 : line.to_i
      absolute_line = buffer.y_base + buffer.y + offset

      max_line = buffer.lines.length - 1
      return nil if absolute_line.negative? || absolute_line > max_line

      id = @next_marker_id
      @next_marker_id += 1
      marker = Marker.new(id, absolute_line)
      @markers << marker

      marker.on_dispose do
        @markers.delete(marker)
      end

      marker
    end

    # --- Buffer Access ---

    # Returns the buffer namespace for accessing buffer content.
    # @return [BufferNamespace]
    def buffer
      @buffer_namespace
    end

    # Returns parser hooks for custom escape sequence handling.
    # @return [ParserNamespace]
    def parser
      @parser_namespace ||= ParserNamespace.new(@terminal.parser)
    end

    # Returns unicode configuration and provider registration APIs.
    # @return [UnicodeNamespace]
    def unicode
      @unicode_namespace ||= UnicodeNamespace.new(@terminal.unicode_handler)
    end

    # Returns the current terminal modes.
    # @return [Hash<Symbol, Boolean>]
    def modes
      @terminal.input_handler.modes
    end

    # Event registration for active buffer changes.
    # @return [Common::Disposable]
    def on_buffer_change(&block)
      @terminal.buffer_set.on(:buffer_change, &block)
    end

    # CamelCase alias.
    def onBufferChange(&block)
      on_buffer_change(&block)
    end

    # Returns the current terminal options.
    # @return [TerminalOptions]
    def options
      @terminal.options
    end

    # Returns option value by name.
    # @param name [Symbol, String]
    # @return [Object]
    def get_option(name)
      @terminal.get_option(name)
    end

    # CamelCase alias.
    # @param name [Symbol, String]
    # @return [Object]
    def getOption(name)
      get_option(name)
    end

    # Sets an option value.
    # @param name [Symbol, String]
    # @param value [Object]
    # @return [TerminalOptions]
    def set_option(name, value)
      @terminal.set_option(name, value)
    end

    # CamelCase alias.
    # @param name [Symbol, String]
    # @param value [Object]
    # @return [TerminalOptions]
    def setOption(name, value)
      set_option(name, value)
    end

    # Option setter.
    # @param new_options [Hash]
    # @return [TerminalOptions]
    def options=(new_options)
      new_options.to_h.each { |name, value| set_option(name, value) }
      options
    end

    # @return [String] current window title from OSC 0/2
    def title
      @terminal.input_handler.title
    end

    # @return [String] current icon name from OSC 0/1
    def icon_name
      @terminal.input_handler.icon_name
    end

    # @return [Array<Hash>] image payloads placed by Sixel/iTerm2 protocols
    def images
      @terminal.input_handler.images
    end

    # Clears cached texture atlas resources (headless no-op).
    # @return [Boolean]
    def clear_texture_atlas
      @terminal.emit(:texture_atlas_clear, { source: :terminal })
      true
    end

    # CamelCase alias.
    alias clearTextureAtlas clear_texture_atlas

    # Resolves renderer-facing colors for a cell without mutating buffer attributes.
    # @param cell [Common::CellData]
    # @return [Hash]
    def cell_colors(cell)
      @terminal.input_handler.color_manager.resolve_cell_colors(cell, options.to_h)
    end

    # Returns renderer-facing cursor policy.
    # @param active [Boolean] whether the terminal is focused
    # @return [Hash]
    def cursor_info(active: true)
      {
        style: active ? @terminal.input_handler.cursor_style : options.cursor_inactive_style,
        blink: active && @terminal.input_handler.cursor_blink,
        width: options.cursor_width.to_i
      }
    end

    # --- Buffer Operations ---

    # Clears the terminal buffer.
    def clear
      clear_selection
      @markers.each(&:dispose)
      @markers.clear
      @last_scroll_position = @terminal.buffer_set.active.y_disp
      @terminal.clear
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_data(&block)
      on(:data, &block)
    end

    def on_open(&block)
      on(:open, &block)
    end

    def on_textarea_input(&block)
      on(:textarea_input, &block)
    end

    def on_composition_start(&block)
      on(:composition_start, &block)
    end

    def on_composition_update(&block)
      on(:composition_update, &block)
    end

    def on_composition_end(&block)
      on(:composition_end, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_binary(&block)
      on(:binary, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_resize(&block)
      on(:resize, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_scroll(&block)
      on(:scroll, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_selection_change(&block)
      on(:selection_change, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_title_change(&block)
      on(:title_change, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_key(&block)
      on(:key, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_bell(&block)
      on(:bell, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_context_menu(&block)
      on(:context_menu, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onCursorMove(&block)
      on(:cursor_move, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onLineFeed(&block)
      on(:line_feed, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onWriteParsed(&block)
      on_write_parsed(&block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onFocus(&block)
      on_focus(&block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onBlur(&block)
      on_blur(&block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_cursor_move(&block)
      on(:cursor_move, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_line_feed(&block)
      on(:line_feed, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_write_parsed(&block)
      on(:write_parsed, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_focus(&block)
      on(:focus, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_blur(&block)
      on(:blur, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def onOptionChange(&block)
      on(:option_change, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_option_change(&block)
      on(:option_change, &block)
    end

    # CamelCase alias.
    # @param block [Proc]
    # @return [Common::Disposable]
    def on_dispose(&block)
      on(:dispose, &block)
    end

    # CamelCase alias.
    def onDispose(&block)
      on_dispose(&block)
    end

    # Resets the terminal to its initial state.
    def reset
      clear_selection
      @markers.each(&:dispose)
      @markers.clear
      @last_scroll_position = @terminal.buffer_set.active.y_disp
      @terminal.reset
    end

    # Scrolls the viewport by the given number of lines.
    # @param amount [Integer]
    def scroll_lines(amount)
      @terminal.scroll_lines(amount)
    end

    # Scrolls the viewport by the given number of lines.
    # CamelCase alias.
    def scrollLines(amount)
      scroll_lines(amount)
    end

    # Scrolls the viewport by the given number of pages.
    # @param count [Integer] number of screen rows per page
    def scroll_pages(count)
      scroll_lines(count.to_i * rows)
    end

    # Scrolls the viewport by the given number of pages.
    # CamelCase alias.
    def scrollPages(count)
      scroll_pages(count)
    end

    # Scrolls the viewport to the specified history row.
    # @param row [Integer] 0-based row
    def scroll_to_line(row)
      active = @terminal.buffer_set.active
      active.y_disp = [[row.to_i, 0].max, active.y_base].min
      @terminal.emit(:scroll, active.y_disp)
    end

    # Scrolls the viewport to the specified history row.
    # CamelCase alias.
    def scrollToLine(row)
      scroll_to_line(row)
    end

    # Scrolls to the top of the scrollback.
    def scroll_to_top
      @terminal.scroll_to_top
    end

    # Scrolls to the top of the scrollback.
    # CamelCase alias.
    def scrollToTop
      scroll_to_top
    end

    # Scrolls to the bottom.
    def scroll_to_bottom
      @terminal.scroll_to_bottom
    end

    # Scrolls to the bottom.
    # CamelCase alias.
    def scrollToBottom
      scroll_to_bottom
    end

    # Scrolls to keep the cursor line visible.
    # CamelCase alias.
    def scrollToCursor
      scroll_to_cursor
    end

    # Scrolls to keep the cursor line visible.
    def scroll_to_cursor
      @terminal.scroll_to_cursor
    end

    # Opens terminal on a host element.
    def open(container = nil, focus = false)
      @container = container || HostElement.new
      @textarea = TextAreaElement.new(self, parent: @container, label: strings["promptLabel"])
      attach_textarea(@container, @textarea)
      @focused = false if focus == false
      @textarea.set_focused(@focused)
      @terminal.emit(:open, { element: @container, textarea: @textarea })
      focus() if focus
      true
    end

    # Focuses the terminal input surface.
    def focus
      @focused = true
      @textarea&.set_focused(true)
      @terminal.emit(:focus, { element: @container, textarea: @textarea })
      true
    end

    # Returns focus state.
    # @return [Boolean]
    def focused?
      @focused
    end

    # CamelCase alias.
    # @return [Boolean]
    def isFocused
      @focused
    end

    # CamelCase alias.
    # @return [Boolean]
    def is_focused
      @focused
    end

    # Removes focus from the terminal input surface.
    def blur
      @focused = false
      @textarea&.set_focused(false)
      @terminal.emit(:blur, { element: @container, textarea: @textarea })
      true
    end

    # Requests a refresh for a row range (no-op for headless runtime).
    #
    # A synthetic render event keeps renderer integrations in sync.
    def refresh(start = nil, end_row = nil)
      first = start.to_i
      last = end_row ? end_row.to_i : rows - 1
      last = rows - 1 if rows.positive? && last >= rows
      last = 0 if last.negative?
      first = 0 if first.negative?
      first = [[first, last].min, rows - 1].min
      @terminal.emit(:render, { start: first, end: last })
      true
    end

    # Selects text from the active buffer.
    # @param column [Integer] start column
    # @param row [Integer] start row
    # @param length [Integer] number of characters to select
    def select(column, row, length)
      set_selection(
        type: :linear,
        column: [column.to_i, 0].max,
        row: [row.to_i, 0].max,
        length: [length.to_i, 0].max
      )
    end

    # Selects the word at the given visible buffer position.
    # @param column [Integer] cell column
    # @param row [Integer] visible row
    def select_word(column, row)
      set_selection(
        type: :word,
        column: [column.to_i, 0].max,
        row: [row.to_i, 0].max
      )
    end

    # CamelCase alias.
    # @return [void]
    def selectWord(column, row)
      select_word(column, row)
    end

    # Selects a URL at the given visible buffer position.
    # @param column [Integer] cell column
    # @param row [Integer] visible row
    def select_url(column, row)
      set_selection(
        type: :url,
        column: [column.to_i, 0].max,
        row: [row.to_i, 0].max
      )
    end

    # CamelCase alias.
    # @return [void]
    def selectUrl(column, row)
      select_url(column, row)
    end

    # Selects the logical line at the given visible row.
    # @param row [Integer] visible row
    # @param include_wrapped [Boolean] whether to include soft-wrapped rows
    def select_line(row, include_wrapped: true)
      set_selection(
        type: :line,
        row: [row.to_i, 0].max,
        include_wrapped: include_wrapped
      )
    end

    # CamelCase alias.
    # @return [void]
    def selectLine(row, include_wrapped: true)
      select_line(row, include_wrapped: include_wrapped)
    end

    # CamelCase alias.
    # @param data [String, nil] optional text override
    # @return [String]
    def copy(data = nil)
      text = data.nil? ? get_selection : data.to_s
      @terminal.input_handler.copy_to_clipboard(text, "c")
      text
    end

    # Applies click selection behavior.
    # @param column [Integer] cell column
    # @param row [Integer] visible row
    # @param click_count [Integer]
    # @param button [Symbol]
    def select_click(column, row, click_count: 1, button: :left)
      if button.to_sym == :right && options.right_click_selects_word
        return select_word(column, row)
      end

      case click_count.to_i
      when 2 then select_word(column, row)
      when 3 then select_line(row)
      else select(column, row, 1)
      end
    end

    # Selects a rectangular cell range in the visible buffer.
    # @param start_column [Integer] starting column
    # @param start_row [Integer] starting row
    # @param end_column [Integer] ending column, inclusive
    # @param end_row [Integer] ending row, inclusive
    def select_rectangle(start_column, start_row, end_column, end_row)
      set_selection(
        type: :rectangle,
        start_column: [start_column.to_i, 0].max,
        start_row: [start_row.to_i, 0].max,
        end_column: [end_column.to_i, 0].max,
        end_row: [end_row.to_i, 0].max
      )
    end

    # CamelCase alias.
    # @return [void]
    def selectRectangle(start_column, start_row, end_column, end_row)
      select_rectangle(start_column, start_row, end_column, end_row)
    end

    # Selects all retained text in the active buffer, including scrollback.
    def select_all(buffer: :active)
      set_selection(
        type: :all,
        buffer: buffer.to_sym
      )
    end

    # CamelCase alias.
    # @return [void]
    def selectAll
      select_all
    end

    # Selection API.
    # Selects lines from start to end (inclusive).
    # @param start [Integer]
    # @param finish [Integer]
    # @return [void]
    def select_lines(start, finish)
      start_row = start.to_i
      end_row = finish.to_i
      start_row, end_row = [start_row, end_row].minmax

      rows = visible_rows
      max_row = rows.length - 1
      return clear_selection if max_row.negative?

      start_row = [[start_row, 0].max, max_row].min
      end_row = [[end_row, 0].max, max_row].min
      return clear_selection if end_row < start_row

      set_selection(
        type: :lines,
        start_row: start_row,
        end_row: end_row
      )
    end

    # CamelCase alias.
    # @param start [Integer]
    # @param finish [Integer]
    # @return [void]
    def selectLines(start, finish)
      select_lines(start, finish)
    end

    # Returns current selected text.
    # CamelCase alias.
    def get_selection
      selection
    end

    # Returns current selected text.
    # CamelCase alias.
    def getSelection
      get_selection
    end

    # Whether any text is currently selected.
    # CamelCase alias.
    def has_selection
      !selection.empty?
    end

    # Whether any text is currently selected.
    # CamelCase alias.
    def hasSelection
      has_selection
    end

    # Selection position helper.
    # @return [Hash, nil]
    def getSelectionPosition
      get_selection_position
    end

    # CamelCase alias.
    # @return [Hash, nil]
    def get_selection_position
      return nil unless @selection
      return nil unless @selection[:type] == :linear

      rows = visible_rows
      return nil if rows.empty?

      row = @selection[:row].to_i
      col = @selection[:column].to_i
      length = @selection[:length].to_i

      return nil if row.negative? || row >= rows.length || length <= 0

      current_row = row
      current_col = [col, rows[row][:line].get_trimmed_length].min
      current_col = 0 if current_col.negative?
      remaining = length
      end_row = current_row
      end_col = current_col

      while remaining.positive? && current_row < rows.length
        available = [rows[current_row][:line].get_trimmed_length - current_col, 0].max
        if remaining <= available
          end_row = current_row
          end_col = current_col + remaining
          break
        end

        remaining -= available
        current_row += 1
        current_col = 0
        end_row = current_row - 1
        end_col = rows[end_row][:line].get_trimmed_length if rows[end_row]
      end

      { start: { x: col, y: row }, end: { x: end_col, y: end_row } }
    end

    # Clears the current selection.
    # CamelCase alias.
    def clearSelection
      clear_selection
    end

    # @return [String] selected text
    def selection
      return "" unless @selection

      case @selection[:type]
      when :linear
        return "" unless @selection[:length].positive?

        selected_buffer_text(@selection[:column], @selection[:row], @selection[:length])
      when :word
        selected_word_text(@selection[:column], @selection[:row])
      when :url
        selected_url_text(@selection[:column], @selection[:row])
      when :line
        selected_line_text(@selection[:row], include_wrapped: @selection[:include_wrapped])
      when :rectangle
        selected_rectangle_text(@selection)
      when :lines
        selected_lines_text(@selection)
      when :all
        selected_all_text(@selection[:buffer])
      else
        ""
      end
    end

    def selected_lines_text(selection)
      start_row = [selection[:start_row], 0].max
      end_row = [selection[:end_row], 0].max
      return "" if start_row > end_row

      (start_row..end_row).map do |row_index|
        row = visible_rows[row_index]
        row ? line_text(row[:line]) : ""
      end.join("\r\n")
    end

    # Clears the current text selection.
    def clear_selection
      set_selection(nil)
    end

    # --- Resize ---

    # Resizes the terminal.
    # @param cols [Integer] new number of columns
    # @param rows [Integer] new number of rows
    def resize(cols, rows)
      @terminal.resize(cols, rows)
    end

    # Handles a wheel gesture, honoring mouse tracking, alternate scroll, and scroll sensitivity.
    # @param amount [Integer] positive scrolls down, negative scrolls up
    # @return [String, Integer, nil] emitted mouse/input sequence or viewport scroll amount
    def mouse_wheel(amount, col: 0, row: 0, modifiers: [])
      event = {
        type: :wheel,
        delta_y: amount.to_i,
        ctrl_key: modifiers.include?(:ctrl) || modifiers.include?(:control),
        alt_key: modifiers.include?(:alt),
        shift_key: modifiers.include?(:shift),
        meta_key: modifiers.include?(:meta),
        col: col,
        row: row
      }

      return nil if @custom_wheel_event_handler&.call(event) == false

      amount = amount.to_i
      return nil if amount.zero?

      if modes[:mouse_tracking_mode]
        button = amount.negative? ? :wheel_up : :wheel_down
        return mouse_event(button: button, col: col, row: row, event: :press, modifiers: modifiers)
      end

      if alternate_scroll?
        sequence = amount.negative? ? "\e[A" : "\e[B"
        payload = sequence * amount.abs
        return input(payload)
      end

      lines = amount * options.scroll_sensitivity.to_i
      scroll_lines(lines)
      lines
    end

    # Encodes a mouse event according to the active DEC mouse mode.
    # @return [String, nil]
    def mouse_event(**options)
      event = mouse_event_payload(options)
      return nil if @custom_mouse_event_handler&.call(event) == false

      @terminal.input_handler.mouse_report(**options)
    end

    # Encodes a focus event according to DEC focus reporting mode.
    # @param focused [Boolean]
    # @return [String, nil]
    def focus_event(focused: true)
      @terminal.input_handler.focus_report(focused)
    end

    # Emits a context menu event with a normalized payload.
    #
    # @param event [Hash, Integer] either a payload hash, or a column value.
    # @param row [Integer, nil] row value when event is not a hash.
    # @return [Hash, false, nil]
    def context_menu_event(event = {}, row = nil)
      payload = context_menu_event_payload(event, row)
      return false if @custom_context_menu_event_handler&.call(payload) == false

      @terminal.emit(:context_menu, payload)
      payload
    end

    def context_menu_event_payload(event = {}, row = nil)
      info = event.is_a?(Hash) ? event : { col: event, row: row }
      col = info[:col]
      row_pos = info[:row]
      mods = Array(info[:modifiers]).map(&:to_sym)

      {
        type: :context_menu,
        col: col,
        row: row_pos,
        x: col,
        y: row_pos,
        client_x: info[:client_x],
        client_y: info[:client_y],
        page_x: info[:page_x],
        page_y: info[:page_y],
        alt_key: mods.include?(:alt),
        ctrl_key: mods.include?(:ctrl) || mods.include?(:control),
        shift_key: mods.include?(:shift),
        meta_key: mods.include?(:meta),
        altKey: mods.include?(:alt),
        ctrlKey: mods.include?(:ctrl) || mods.include?(:control),
        shiftKey: mods.include?(:shift),
        metaKey: mods.include?(:meta),
        dom_event: info[:dom_event] || info[:domEvent] || nil
      }.compact
    end

    # --- Events ---

    # Registers an event listener.
    # @param event [Symbol] the event name
    # @yield the callback block
    # @return [Common::Disposable]
    def on(event, &block)
      @terminal.on(event, &block)
    end

    # Attach a custom key event handler.
    # Return a disposable so callers can remove the handler.
    #
    # @yield [Hash] key event payload
    # @return [Common::Disposable]
    def attach_custom_key_event_handler(&block)
      raise ArgumentError, "A key event handler block is required" unless block

      @custom_key_event_handler = block
      Common::Disposable.new do
        @custom_key_event_handler = nil if @custom_key_event_handler.equal?(block)
      end
    end

    # Attach a custom wheel event handler.
    # Return a disposable so callers can remove the handler.
    #
    # @yield [Hash] wheel event payload
    # @return [Common::Disposable]
    def attach_custom_wheel_event_handler(&block)
      raise ArgumentError, "A wheel event handler block is required" unless block

      @custom_wheel_event_handler = block
      Common::Disposable.new do
        @custom_wheel_event_handler = nil if @custom_wheel_event_handler.equal?(block)
      end
    end

    # Attach a custom mouse event handler.
    # Return a disposable so callers can remove the handler.
    #
    # @yield [Hash] mouse event payload
    # @return [Common::Disposable]
    def attach_custom_mouse_event_handler(&block)
      raise ArgumentError, "A mouse event handler block is required" unless block

      @custom_mouse_event_handler = block
      Common::Disposable.new do
        @custom_mouse_event_handler = nil if @custom_mouse_event_handler.equal?(block)
      end
    end

    # CamelCase alias.
    def attachCustomMouseEventHandler(&block)
      attach_custom_mouse_event_handler(&block)
    end

    # Attach a custom context menu event handler.
    # Return a disposable so callers can remove the handler.
    #
    # @yield [Hash] context menu payload
    # @return [Common::Disposable]
    def attach_custom_context_menu_event_handler(&block)
      raise ArgumentError, "A context menu event handler block is required" unless block

      @custom_context_menu_event_handler = block
      Common::Disposable.new do
        @custom_context_menu_event_handler = nil if @custom_context_menu_event_handler.equal?(block)
      end
    end

    # CamelCase alias.
    # @return [Common::Disposable]
    def attachCustomContextMenuEventHandler(&block)
      attach_custom_context_menu_event_handler(&block)
    end

    def mouse_event_payload(options)
      mods = Array(options[:modifiers]).map(&:to_sym)
      {
        type: :mouse,
        button: options[:button],
        buttons: options[:button],
        x: options[:col],
        y: options[:row],
        col: options[:col],
        row: options[:row],
        event: options[:event] || :press,
        pixels: [options[:pixel_col], options[:pixel_row]],
        pixel_x: options[:pixel_col],
        pixel_y: options[:pixel_row],
        ctrl_key: mods.include?(:ctrl) || mods.include?(:control),
        alt_key: mods.include?(:alt),
        shift_key: mods.include?(:shift),
        meta_key: mods.include?(:meta),
        ctrlKey: mods.include?(:ctrl) || mods.include?(:control),
        altKey: mods.include?(:alt),
        shiftKey: mods.include?(:shift),
        metaKey: mods.include?(:meta)
      }
    end
    # --- Addons ---

    def web_links_addon
      existing = @addons.find do |addon|
        addon.is_a?(Addon::WebLinks)
      end
      return existing if existing

      addon = Addon::WebLinks.new
      load_addon(addon)
      addon
    end

    # Loads an addon into the terminal.
    # @param addon [Addon::Base] the addon to load
    def load_addon(addon)
      addon.activate(self)
      @addons << addon
    end

    # Returns current registered markers.
    # @return [Array<Marker>]
    def markers
      return [] if @terminal.buffer_set.active.equal?(@terminal.buffer_set.alt)

      @markers.dup
    end

    # CamelCase alias.
    # @return [Array<Marker>]
    def getMarkers
      markers
    end

    # Loads an addon into the terminal.
    # CamelCase alias.
    def loadAddon(addon)
      load_addon(addon)
    end

    # Disposes of the terminal and all loaded addons.
    def dispose
      return if @disposed

      @disposed = true
      @terminal.emit(:dispose)
      @link_matchers.each_value(&:dispose)
      @link_matchers.clear
      @markers.each(&:dispose)
      @markers.clear
      @addons.each(&:dispose)
      @addons.clear
      @terminal.dispose
    end

    # Provides access to internal terminal for addons.
    # @return [Headless::HeadlessTerminal]
    # @api private
    def internal
      @terminal
    end

    def on_terminal_scroll(position)
      return if position.nil?

      @last_scroll_position = position.to_i
    end

    private

    def attach_textarea(container, textarea)
      return unless container && textarea

      if container.respond_to?(:append_child)
        container.append_child(textarea)
      elsif container.respond_to?(:appendChild)
        container.appendChild(textarea)
      end
    end

    def input_surface_payload(data, was_user_input:)
      {
        data: data,
        value: @textarea&.value,
        textarea: @textarea,
        element: @container,
        was_user_input: was_user_input
      }
    end

    def update_composition(data, active:)
      @composition = {
        active: active,
        data: data.to_s
      }
      @textarea&.set_composition(@composition[:data], active: active)
      @composition
    end

    def composition_payload(event, data, committed: false)
      {
        event: event,
        data: data,
        active: @composition[:active],
        committed: committed,
        textarea: @textarea,
        element: @container
      }
    end

    def render_decorations(_payload = nil)
      return if @decorations.empty?

      buffer = @terminal.buffer_set.active
      viewport_start = buffer.y_disp
      viewport_end = viewport_start + rows - 1

      @decorations.dup.each do |decoration|
        decoration.render(viewport_start: viewport_start, viewport_end: viewport_end, cols: cols)
      end
    end

    def set_selection(selection)
      @selection = selection
      @terminal.emit(:selection_change, selection_change_payload)
      @selection
    end

    def normalize_write_data(data)
      return data if data.is_a?(String)
      return data.pack("C*") if data.is_a?(Array) && data.all? { |byte| byte.is_a?(Integer) }

      data.to_s
    end

    def normalize_was_user_input(was_user_input, kwargs)
      if was_user_input.is_a?(Hash)
        kwargs = was_user_input.merge(kwargs)
        was_user_input = true
      end

      return kwargs[:was_user_input] if kwargs.key?(:was_user_input)
      return kwargs[:wasUserInput] if kwargs.key?(:wasUserInput)

      was_user_input
    end

    # Normalizes matcher options.
    def normalize_link_matcher_options(options)
      normalized = options.to_h
      {
        match_index: normalized[:matchIndex] || normalized[:match_index],
        validation: normalized[:validation],
        url: normalized[:url],
        handler: normalized[:handler],
        hover: normalized[:hover],
        leave: normalized[:leave]
      }.compact
    end

    # Converts regex matches to provider links.
    def scan_link_matches(text, matcher, handler, options, _row)
      normalized_handler = handler || options[:handler]
      match_index = [options[:match_index].to_i, 0].max
      validation = options[:validation]

      text.scan(matcher).filter_map do
        match = Regexp.last_match
        match_text = match[match_index]
        next if match_text.nil?

        next if validation && validation.call(match_text) == false

        start = match.begin(match_index)
        next if start.nil?

        url = match_text.to_s
        url = options[:url].call(match_text) if options[:url]
        next if url.nil?

        text_label = match_text.to_s

        {
          url: url,
          text: text_label,
          start: start,
          length: text_label.length,
          activate: matcher_activate_handler(normalized_handler, options),
          hover: matcher_hover_handler(options),
          leave: matcher_leave_handler(options)
        }
      end
    end

    # Builds an activate callback for a link matcher.
    def matcher_activate_handler(handler, _options)
      return nil unless handler

      lambda do |link|
        if handler.arity.zero?
          handler.call
        elsif handler.arity == 1
          handler.call(link[:url])
        elsif handler.arity == 2
          handler.call(nil, link[:url])
        else
          handler.call(nil, link[:url], link)
        end
      end
    end

    # Builds an optional hover callback from matcher options.
    def matcher_hover_handler(options)
      callback = options[:hover]
      return nil unless callback

      lambda do |link|
        case callback.arity
        when 0 then callback.call
        when 1 then callback.call(link[:url])
        when 2 then callback.call(nil, link[:url])
        else callback.call(nil, link[:url], link)
        end
      end
    end

    # Builds an optional leave callback from matcher options.
    def matcher_leave_handler(options)
      callback = options[:leave]
      return nil unless callback

      lambda do |link|
        case callback.arity
        when 0 then callback.call
        when 1 then callback.call(link[:url])
        when 2 then callback.call(nil, link[:url])
        else callback.call(nil, link[:url], link)
        end
      end
    end

    def selection_change_payload
      return nil unless @selection

      text = selection
      position = get_selection_position

      {
        selection: @selection.dup,
        selection_text: text,
        selectionText: text,
        start: position ? position[:start] : nil,
        end: position ? position[:end] : nil,
        start_pos: position ? position[:start] : nil,
        end_pos: position ? position[:end] : nil,
        startPos: position ? position[:start] : nil,
        endPos: position ? position[:end] : nil,
        empty: text.empty?
      }
    end

    def key_event_payload(key, modifiers, text)
      key_string = key.to_s
      key_code = key_string.length == 1 ? key_string.ord : nil
      alt_key = modifiers.include?(:alt) || modifiers.include?(:meta)
      shift_key = modifiers.include?(:shift)
      ctrl_key = modifiers.include?(:ctrl) || modifiers.include?(:control)
      meta_key = modifiers.include?(:meta)
      dom_event = {
        key: key_string,
        code: key_string,
        keyCode: key_code,
        key_code: key_code,
        altKey: alt_key,
        shiftKey: shift_key,
        ctrlKey: ctrl_key,
        metaKey: meta_key,
        type: :keydown,
        text: text,
        repeat: false
      }
      {
        key: key_string,
        code: key_string,
        key_code: key_code,
        keyCode: key_code,
        text: text,
        alt_key: alt_key,
        ctrl_key: ctrl_key,
        shift_key: shift_key,
        meta_key: meta_key,
        altKey: alt_key,
        ctrlKey: ctrl_key,
        shiftKey: shift_key,
        metaKey: meta_key,
        dom_event: dom_event,
        type: dom_event[:type],
        which: key_code,
        raw: {
          key: key,
          modifiers: modifiers
        }
      }
    end

    def visible_rows
      active = buffer.active
      collect_rows(active.y_disp, active.rows)
    end

    def all_rows(scope = :active)
      selected_buffer = buffer_for_scope(scope)
      collect_rows(0, selected_buffer.lines.length, selected_buffer)
    end

    def collect_rows(start_index, count, selected_buffer = buffer.active)
      last_index = [start_index + count, selected_buffer.lines.length].min
      rows = (start_index...last_index).filter_map do |index|
        line = selected_buffer.lines[index]
        next unless line

        { line: line, wrapped_to_next: line.is_wrapped }
      end

      rows.pop while rows.last && line_empty?(rows.last[:line])
      rows
    end

    def line_empty?(line)
      line.get_trimmed_length.zero?
    end

    def selected_all_text(scope = :active)
      join_row_text(all_rows(scope))
    end

    def selected_buffer_text(column, row, length)
      rows = visible_rows
      current_row = [[row, 0].max, rows.length].min
      current_col = [column, 0].max
      remaining = length
      result = +""
      first_line = true
      previous_wrapped = false

      while remaining.positive? && current_row < rows.length
        row_info = rows[current_row]
        line = row_info[:line]
        result << "\r\n" unless first_line || previous_wrapped
        first_line = false

        available = [line.get_trimmed_length - current_col, 0].max
        take = [available, remaining].min
        result << line_text(
          line,
          start_col: current_col,
          end_col: current_col + take,
          row: current_row
        )
        remaining -= take
        previous_wrapped = row_info[:wrapped_to_next]
        current_row += 1
        current_col = 0
      end

      result
    end

    def selected_word_text(column, row)
      row_info = visible_rows[[row, 0].max]
      return "" unless row_info

      segments = line_segments(row_info[:line])
      target = segments.find_index { |segment| column >= segment[:start_col] && column < segment[:end_col] }
      target ||= segments.length - 1 if segments.any? && column >= segments.last[:end_col]
      return "" unless target

      separators = options.word_separator.to_s.each_char.to_a
      return "" if separators.include?(segments[target][:text])

      first = target
      first -= 1 while first.positive? && !separators.include?(segments[first - 1][:text])

      last = target
      last += 1 while last < segments.length - 1 && !separators.include?(segments[last + 1][:text])

      segments[first..last].map { |segment| segment[:text] }.join
    end

    def selected_url_text(column, row)
      group = logical_group_for_row(row)
      return "" unless group

      offset = offset_for_cell(group[:segments], column, row)
      return "" unless offset

      group[:text].to_enum(:scan, URL_SELECTION_REGEX).each do
        match = Regexp.last_match
        url = trim_url(match[0])
        start = match.begin(0)
        finish = start + url.length
        return url if offset >= start && offset < finish
      end

      ""
    end

    def selected_line_text(row, include_wrapped: true)
      if include_wrapped
        group = logical_group_for_row(row)
        return group ? group[:text].rstrip : ""
      end

      row_info = visible_rows[[row, 0].max]
      row_info ? line_text(row_info[:line], row: [row, 0].max) : ""
    end

    def selected_rectangle_text(selection)
      rows = visible_rows
      first_row, last_row = [selection[:start_row], selection[:end_row]].minmax
      first_col, last_col = [selection[:start_column], selection[:end_column]].minmax

      (first_row..last_row).map do |row_index|
        row_info = rows[row_index]
        row_info ? line_text(
          row_info[:line],
          start_col: first_col,
          end_col: last_col + 1,
          trim_right: false,
          row: row_index
        ) : ""
      end.join("\r\n")
    end

    def join_row_text(rows)
      result = +""
      rows.each_with_index do |row_info, index|
        result << "\r\n" if index.positive? && !rows[index - 1][:wrapped_to_next]
        result << line_text(row_info[:line], row: index)
      end
      result
    end

    def line_text(line, start_col: 0, end_col: nil, trim_right: true, row: nil)
      text = line_segments(line, start_col: start_col, end_col: end_col, trim_right: trim_right)
        .map { |segment| segment[:text] }
        .join
      apply_character_joiners(text, row)
    end

    def apply_character_joiners(text, row = nil)
      return text if @character_joiners.empty?

      @character_joiners.each_value do |joiner|
        case joiner.arity
        when 0
          joiner.call
        when 1
          joiner.call(text)
        else
          joiner.call(text, row)
        end
      end

      text
    end

    def line_segments(line, start_col: 0, end_col: nil, trim_right: true)
      start_col = [start_col, 0].max
      max_end = trim_right ? line.get_trimmed_length : line.length
      end_col = end_col ? [end_col, max_end].min : max_end
      return [] if end_col <= start_col

      segments = []
      column = 0
      while column < end_col
        cell = line.get_cell(column)
        width = [(cell&.width || 1).to_i, 1].max
        next_column = column + width

        if cell && cell.width != 0 && next_column > start_col
          segments << {
            text: cell.has_content? ? cell.char : " ",
            start_col: column,
            end_col: next_column
          }
        end

        column = next_column
      end
      segments
    end

    def logical_group_for_row(row)
      row = [row.to_i, 0].max
      logical_visible_groups.find { |group| row >= group[:start_row] && row <= group[:end_row] }
    end

    def logical_visible_groups
      groups = []
      current = nil

      visible_rows.each_with_index do |row_info, row|
        current ||= { text: +"", segments: [], start_row: row, end_row: row }
        append_logical_segments(current, row_info, row)
        current[:end_row] = row

        next if row_info[:wrapped_to_next]

        groups << current
        current = nil
      end
      groups << current if current
      groups
    end

    def append_logical_segments(group, row_info, row)
      line_segments(row_info[:line], trim_right: !row_info[:wrapped_to_next]).each do |segment|
        start = group[:text].length
        group[:text] << segment[:text]
        group[:segments] << segment.merge(row: row, start: start, end: group[:text].length)
      end
    end

    def offset_for_cell(segments, column, row)
      segment = segments.find do |item|
        item[:row] == row && column >= item[:start_col] && column < item[:end_col]
      end
      segment ||= segments.find { |item| item[:row] == row && column == item[:end_col] }
      segment&.fetch(:start)
    end

    def trim_url(url)
      url = url.dup
      loop do
        last = url[-1]
        break unless last

        if URL_TRAILING_PUNCTUATION.include?(last)
          url.chop!
        elsif last == ")" && url.count(")") > url.count("(")
          url.chop!
        else
          break
        end
      end
      url
    end

    def buffer_for_scope(scope)
      case scope.to_sym
      when :normal then buffer.normal
      when :alt, :alternate then buffer.alt
      else buffer.active
      end
    end

    def alternate_scroll?
      options.alternate_scroll_mode &&
        @terminal.buffer_set.active.equal?(@terminal.buffer_set.alt)
    end

    def key_modifiers(modifiers)
      symbols = modifiers.map(&:to_sym)
      return symbols unless options.mac_option_is_meta && symbols.include?(:option)

      (symbols - [:option]) | [:meta]
    end
  end

  # Provides access to active/normal/alt buffers with a clean API.
  class BufferNamespace
    include Common::EventEmitter

    # @return [Common::Buffer] the currently active buffer
    def active
      @buffer_set.active
    end

    # @return [Common::Buffer] the normal buffer
    def normal
      @buffer_set.normal
    end

    # @return [Common::Buffer] the alternate buffer
    def alt
      @buffer_set.alt
    end

    # CamelCase alias.
    alias alternate alt

    # CamelCase alias for buffer change events.
    def on_buffer_change(&block)
      on(:buffer_change, &block)
    end

    alias onBufferChange on_buffer_change

    private

    def initialize(buffer_set)
      @buffer_set = buffer_set
    end
  end

  class ParserNamespace
    def initialize(parser)
      @parser = parser
    end

    def register_csi_handler(id, &block)
      @parser.set_csi_handler(id, &block)
    end

    def set_print_handler(&block)
      @parser.set_print_handler(&block)
    end

    def set_execute_handler(code, &block)
      @parser.set_execute_handler(code, &block)
    end

    def register_esc_handler(id, &block)
      @parser.set_esc_handler(id, &block)
    end

    def register_osc_handler(id, &block)
      @parser.set_osc_handler(id, &block)
    end

    def register_dcs_handler(id, &block)
      @parser.set_dcs_handler(id, &block)
    end

    # CamelCase aliases.
    alias set_csi_handler register_csi_handler
    alias set_esc_handler register_esc_handler
    alias set_osc_handler register_osc_handler
    alias set_dcs_handler register_dcs_handler
    alias setCsiHandler register_csi_handler
    alias setEscHandler register_esc_handler
    alias setOscHandler register_osc_handler
    alias setDcsHandler register_dcs_handler
    alias registerCsiHandler register_csi_handler
    alias registerEscHandler register_esc_handler
    alias registerOscHandler register_osc_handler
    alias registerDcsHandler register_dcs_handler
    alias setPrintHandler set_print_handler
    alias setExecuteHandler set_execute_handler
  end

  class UnicodeNamespace
    def initialize(unicode_handler)
      @unicode_handler = unicode_handler
    end

    def active_version
      @unicode_handler.active_version
    end

    def active_version=(version)
      @unicode_handler.active_version = version
    end

    def versions
      @unicode_handler.versions
    end

    # CamelCase aliases.
    alias activeVersion active_version
    alias activeVersion= active_version=

    def register(version, provider = nil)
      @unicode_handler.register(version, provider)
    end
  end
end
