# frozen_string_literal: true

require "time"

require_relative "../base"

module RTerm
  module Addon
    class HostIntegration < Base
      include Common::EventEmitter

      TERMINAL_EVENTS = {
        open: :mount,
        render: :render,
        resize: :resize,
        scroll: :scroll,
        selection_change: :selection_change,
        focus: :focus,
        blur: :blur,
        textarea_input: :textarea_input,
        composition_start: :composition_start,
        composition_update: :composition_update,
        composition_end: :composition_end,
        key: :key,
        data: :input,
        binary: :binary,
        bell: :bell,
        title_change: :title,
        screen_reader: :screen_reader,
        accessibility: :accessibility,
        clipboard: :clipboard_write,
        clipboard_request: :clipboard_read_request,
        font_load: :font_load,
        font_measure: :font_measure,
        font_relayout: :font_relayout,
        renderer_change: :renderer_change,
        screen_render: :screen,
        raster_render: :raster
      }.freeze

      attr_reader :commands, :transport, :clipboard_store

      def initialize(transport: nil, auto_mount: false, history_limit: 200)
        @transport = transport
        @auto_mount = !!auto_mount
        @history_limit = [history_limit.to_i, 1].max
        @commands = []
        @clipboard_store = {}
        @pending_clipboard_requests = []
        @disposables = []
        @next_command_id = 1
        @active = false
      end

      def activate(terminal)
        super
        @active = true
        subscribe_terminal_events
        command(:activate, state)
        mount if @auto_mount
      end

      def dispose
        @disposables.each(&:dispose)
        @disposables.clear
        @active = false
        command(:dispose, state) if @terminal
        @terminal = nil
        super
      end

      def active?
        @active
      end

      def attach_transport(transport, flush: true)
        @transport = transport
        flush_commands if flush
        state
      end

      def detach_transport
        @transport = nil
        state
      end

      def mount(container = nil, focus: false)
        ensure_active!

        @terminal.open(container, focus)
        surface_payload
      end

      def request_render(start_row: 0, end_row: nil)
        ensure_active!

        @terminal.refresh(start_row, end_row || @terminal.rows - 1)
      end

      def receive(event = nil, **kwargs)
        ensure_active!

        data = normalize_hash(event || {}).merge(normalize_hash(kwargs))
        type = event_type(data.delete(:type) || data.delete(:event))
        result = handle_host_event(type, data)
        payload = { event: type, result: safe_value(result) }
        emit(:host_event, payload)
        payload
      end

      def flush_commands
        return [] unless @transport

        @commands.each { |queued| deliver(queued) }
      end

      def clear_commands
        @commands.clear
      end

      def pending_clipboard_requests
        @pending_clipboard_requests.map { |request| safe_value(request) }
      end

      def state
        {
          active: @active,
          mounted: !@terminal&.element.nil?,
          transport_attached: !@transport.nil?,
          pending_commands: @commands.length,
          pending_clipboard_requests: @pending_clipboard_requests.length,
          cols: @terminal&.cols,
          rows: @terminal&.rows
        }.compact
      end

      def on_command(&block)
        on(:command, &block)
      end

      def on_host_event(&block)
        on(:host_event, &block)
      end

      alias active active?
      alias attachTransport attach_transport
      alias detachTransport detach_transport
      alias requestRender request_render
      alias receiveEvent receive
      alias hostEvent receive
      alias flushCommands flush_commands
      alias clearCommands clear_commands
      alias pendingClipboardRequests pending_clipboard_requests
      alias clipboardStore clipboard_store
      alias onCommand on_command
      alias onHostEvent on_host_event

      private

      def subscribe_terminal_events
        TERMINAL_EVENTS.each do |event, command_type|
          @disposables << @terminal.on(event) { |payload| handle_terminal_event(command_type, payload) }
        end
      end

      def handle_terminal_event(command_type, payload)
        track_clipboard_request(payload) if command_type == :clipboard_read_request
        payload = case command_type
        when :mount then surface_payload
        when :render then render_payload(payload)
        else payload
        end
        command(command_type, safe_value(payload))
      end

      def handle_host_event(type, data)
        case type
        when :input then @terminal.input(text_value(data), user_input?(data))
        when :paste then @terminal.paste(text_value(data))
        when :binary then @terminal.binary(text_value(data).b)
        when :key then @terminal.key_event(data[:key], modifiers: Array(data[:modifiers]), text: data[:text])
        when :mouse then forward_mouse(data)
        when :wheel then @terminal.mouse_wheel(number_value(data, :amount, :delta_y), **pointer_options(data))
        when :focus then @terminal.focus
        when :blur then @terminal.blur
        when :resize then resize_terminal(data)
        when :viewport, :cell_measure, :font_measure then measure_cell(data)
        when :clipboard, :clipboard_text then receive_clipboard(data)
        when :composition_start then @terminal.composition_start(text_value(data))
        when :composition_update then @terminal.composition_update(text_value(data))
        when :composition_end then @terminal.composition_end(text_value(data), commit: data.fetch(:commit, true))
        when :context_menu then @terminal.context_menu_event(data)
        when :scroll then scroll_terminal(data)
        when :render then request_render(start_row: data.fetch(:start, 0), end_row: data[:end])
        else
          raise ArgumentError, "unknown host event: #{type}"
        end
      end

      def forward_mouse(data)
        sequence = @terminal.mouse_event(**pointer_options(data).merge(button: data[:button], event: data[:mouse_event] || data[:action] || :press))
        @terminal.input(sequence) if sequence && data.fetch(:emit, true)
        sequence
      end

      def resize_terminal(data)
        measure_cell(data) if data.key?(:cell_width) || data.key?(:cell_height)
        @terminal.resize(
          optional_number(data, :cols, :columns) || @terminal.cols,
          optional_number(data, :rows) || @terminal.rows
        )
      end

      def measure_cell(data)
        width = number_value(data, :cell_width, :width)
        height = number_value(data, :cell_height, :height)
        measurement = @terminal.internal.services.get(Services::CHAR_SIZE_SERVICE).measure(width: width, height: height)
        command(:font_measure, measurement)
        measurement
      end

      def receive_clipboard(data)
        text = text_value(data)
        selection = data[:selection] || "c"
        clipboard_selections(selection).each { |name| @clipboard_store[name] = text }
        fulfill_clipboard_requests(selection, text)
        { selection: selection, text: text }
      end

      def scroll_terminal(data)
        return @terminal.scroll_to_line(number_value(data, :line, :row)) if data.key?(:line) || data.key?(:row)

        @terminal.scroll_lines(number_value(data, :amount, :delta_y))
      end

      def command(type, payload = {})
        item = {
          id: @next_command_id,
          type: type,
          payload: safe_value(payload),
          created_at: Time.now.utc.iso8601(6)
        }
        @next_command_id += 1
        @commands << item
        @commands.shift while @commands.length > @history_limit
        emit(:command, item)
        deliver(item)
        item
      end

      def deliver(item)
        return unless @transport

        if @transport.respond_to?(:call)
          @transport.call(item)
        elsif @transport.respond_to?(:write)
          @transport.write(item)
        elsif @transport.respond_to?(:<<)
          @transport << item
        end
      end

      def surface_payload
        {
          element: @terminal.element,
          textarea: @terminal.textarea,
          live_region: @terminal.live_region,
          accessibility: @terminal.accessibility_snapshot,
          cols: @terminal.cols,
          rows: @terminal.rows,
          options: @terminal.options.to_h
        }
      end

      def render_payload(payload)
        data = normalize_hash(payload || {})
        {
          start: number_value(data, :start),
          end: data.key?(:end) ? number_value(data, :end) : @terminal.rows - 1,
          accessibility_tree: @terminal.accessibility_tree
        }
      end

      def track_clipboard_request(payload)
        data = normalize_hash(payload || {})
        @pending_clipboard_requests << data
      end

      def fulfill_clipboard_requests(selection, text)
        matches = @pending_clipboard_requests.select do |request|
          requested = Array(request[:selections])
          requested.empty? || (requested & clipboard_selections(selection)).any?
        end
        matches.each do |request|
          sequence = @terminal.internal.input_handler.respond_to_clipboard(request[:selection] || selection, text)
          command(:clipboard_response, selection: request[:selection] || selection, sequence: sequence)
          @pending_clipboard_requests.delete(request)
        end
      end

      def pointer_options(data)
        {
          col: number_value(data, :col, :x),
          row: number_value(data, :row, :y),
          pixel_col: optional_number(data, :pixel_col, :pixel_x),
          pixel_row: optional_number(data, :pixel_row, :pixel_y),
          modifiers: Array(data[:modifiers])
        }.compact
      end

      def text_value(data)
        (data[:data] || data[:text] || data[:value] || "").to_s
      end

      def user_input?(data)
        return data[:was_user_input] unless data[:was_user_input].nil?

        true
      end

      def number_value(data, *keys)
        value = optional_number(data, *keys)
        value.nil? ? 0 : value
      end

      def optional_number(data, *keys)
        key = keys.find { |candidate| data.key?(candidate) }
        value = data[key] if key
        value.nil? ? nil : value.to_f.then { |number| number == number.to_i ? number.to_i : number }
      end

      def event_type(value)
        normalize_key(value || :input)
      end

      def normalize_hash(value)
        return {} unless value.respond_to?(:to_h)

        value.to_h.each_with_object({}) do |(key, item), result|
          result[normalize_key(key)] = item
        end
      end

      def normalize_key(key)
        key.to_s
           .tr("-", "_")
           .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
           .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
           .downcase
           .to_sym
      end

      def clipboard_selections(selection)
        chars = selection.to_s.empty? ? ["c"] : selection.to_s.chars
        chars.map { |name| clipboard_selection_alias(name) }
      end

      def clipboard_selection_alias(name)
        case name
        when "c" then "clipboard"
        when "p" then "primary"
        when "q" then "secondary"
        when "s" then "select"
        when "0".."7" then "cut#{name}"
        else name
        end
      end

      def safe_value(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key] = safe_value(item) }
        when Array
          value.map { |item| safe_value(item) }
        when Time
          value.utc.iso8601(6)
        else
          value.respond_to?(:to_h) && !value.is_a?(String) ? safe_value(value.to_h) : value
        end
      end

      def ensure_active!
        raise RuntimeError, "Host integration addon is not active" unless @terminal
      end
    end
  end
end
