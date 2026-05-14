# frozen_string_literal: true

require_relative "../common/event_emitter"
require_relative "base"

module RTerm
  module Addon
    class RendererLifecycle < Base
      include Common::EventEmitter

      DEFAULT_CAPABILITIES = {}.freeze
      RENDERER_TYPE = :renderer

      attr_reader :renderer, :context, :host, :shadow_root

      def initialize(options = {})
        @options = normalize_options(options)
        @renderer = @options[:renderer]
        @context = @options[:context]
        @host = @options[:host]
        @shadow_root = @options[:shadow_root]
        @viewport = normalize_viewport(@options.fetch(:viewport, {}))
        @scrollbar = normalize_scrollbar(@options.fetch(:scrollbar, {}))
        @capabilities = default_capabilities.merge(normalize_hash(@options.fetch(:capabilities, {})))
        @disposables = []
        @active = false
        @context_lost = false
        @last_render = nil
        @last_resize = nil
        @last_option_change = nil
        @render_cache_clears = 0
      end

      def activate(terminal)
        super
        @active = true
        @last_resize = viewport_payload
        subscribe_terminal_events
        emit_change(:activate)
      end

      def dispose
        @disposables.each(&:dispose)
        @disposables.clear
        @active = false
        emit_change(:dispose)
        @terminal = nil
        super
      end

      def active?
        @active
      end

      def context_lost?
        @context_lost
      end

      def renderer_type
        self.class::RENDERER_TYPE
      end

      def capabilities
        deep_dup(@capabilities.merge(type: renderer_type))
      end

      def state
        {
          active: @active,
          type: renderer_type,
          context_lost: @context_lost,
          capabilities: capabilities,
          host_attached: !@host.nil?,
          shadow_root_attached: !@shadow_root.nil?,
          viewport: viewport,
          scrollbar: scrollbar,
          last_render: deep_dup(@last_render),
          last_resize: deep_dup(@last_resize),
          last_option_change: deep_dup(@last_option_change),
          render_cache_clears: @render_cache_clears
        }
      end

      def last_render
        deep_dup(@last_render)
      end

      def last_resize
        deep_dup(@last_resize)
      end

      def render_cache_clears
        @render_cache_clears
      end

      def viewport
        deep_dup(viewport_payload)
      end

      def scrollbar
        deep_dup(@scrollbar)
      end

      def attach_renderer(renderer, context: @context, capabilities: nil)
        @renderer = renderer
        @context = context
        @capabilities = @capabilities.merge(normalize_hash(capabilities)) if capabilities
        emit_change(:attach_renderer)
        state
      end

      def attach_host(host, shadow_root: nil, viewport: nil)
        @host = host
        @shadow_root = shadow_root unless shadow_root.nil?
        @viewport = normalize_viewport(@viewport.merge(normalize_hash(viewport))) if viewport
        payload = event_payload(:host_attach).merge(host: @host, shadow_root: @shadow_root, viewport: self.viewport)
        emit(:host_attach, payload)
        emit_terminal(renderer_event(:host_attach), payload)
        emit_change(:host_attach)
        state
      end

      def detach_host
        return state unless @host || @shadow_root

        @host = nil
        @shadow_root = nil
        payload = event_payload(:host_detach).merge(viewport: viewport)
        emit(:host_detach, payload)
        emit_terminal(renderer_event(:host_detach), payload)
        emit_change(:host_detach)
        state
      end

      def update_viewport(attributes = nil, **kwargs)
        data = normalize_hash(attributes || {}).merge(normalize_hash(kwargs))
        @viewport = normalize_viewport(@viewport.merge(data))
        @last_resize = viewport_payload.slice(:cols, :rows)
        payload = event_payload(:viewport).merge(viewport: viewport)
        emit(:viewport, payload)
        emit_terminal(renderer_event(:viewport), payload)
        emit_change(:viewport)
        viewport
      end

      def update_scrollbar(attributes = nil, **kwargs)
        data = normalize_hash(attributes || {}).merge(normalize_hash(kwargs))
        @scrollbar = normalize_scrollbar(@scrollbar.merge(data))
        payload = event_payload(:scrollbar).merge(scrollbar: scrollbar)
        emit(:scrollbar, payload)
        emit_terminal(renderer_event(:scrollbar), payload)
        emit_change(:scrollbar)
        scrollbar
      end

      def lose_context(reason = nil)
        return false if @context_lost

        @context_lost = true
        payload = event_payload(:context_loss, reason: reason)
        emit(:context_loss, payload)
        emit_terminal(renderer_event(:context_loss), payload)
        emit_change(:context_loss)
        true
      end

      def restore_context(context = nil)
        return false unless @context_lost

        @context = context unless context.nil?
        @context_lost = false
        payload = event_payload(:context_restore)
        emit(:context_restore, payload)
        emit_terminal(renderer_event(:context_restore), payload)
        emit_change(:context_restore)
        @terminal&.refresh(0, @terminal.rows - 1)
        true
      end

      def clear_render_cache
        return record_render_cache_clear({ source: :addon }) unless @terminal

        @terminal.clear_texture_atlas
      end

      def on_context_loss(&block)
        on(:context_loss, &block)
      end

      def on_context_restore(&block)
        on(:context_restore, &block)
      end

      def on_render_cache_clear(&block)
        on(cache_event_name, &block)
      end

      def on_host_attach(&block)
        on(:host_attach, &block)
      end

      def on_viewport(&block)
        on(:viewport, &block)
      end

      def on_scrollbar(&block)
        on(:scrollbar, &block)
      end

      def on_change(&block)
        on(:change, &block)
      end

      alias active active?
      alias is_context_lost context_lost?
      alias isContextLost context_lost?
      alias rendererType renderer_type
      alias shadowRoot shadow_root
      alias lastRender last_render
      alias lastResize last_resize
      alias renderCacheClears render_cache_clears
      alias attachHost attach_host
      alias detachHost detach_host
      alias updateViewport update_viewport
      alias updateScrollbar update_scrollbar
      alias attachRenderer attach_renderer
      alias loseContext lose_context
      alias restoreContext restore_context
      alias clearRenderCache clear_render_cache
      alias onContextLoss on_context_loss
      alias onContextRestore on_context_restore
      alias onRenderCacheClear on_render_cache_clear
      alias onHostAttach on_host_attach
      alias onViewport on_viewport
      alias onScrollbar on_scrollbar
      alias onChange on_change

      private

      def subscribe_terminal_events
        @disposables << @terminal.on(:render) { |payload| handle_render(payload) }
        @disposables << @terminal.on(:resize) { |payload| handle_resize(payload) }
        @disposables << @terminal.on(:option_change) { |payload| handle_option_change(payload) }
        @disposables << @terminal.on(:texture_atlas_clear) { |payload| record_render_cache_clear(payload) }
      end

      def handle_render(payload)
        @last_render = normalize_render_payload(payload)
        emit(:render, deep_dup(@last_render))
      end

      def handle_resize(payload)
        @last_resize = normalize_resize_payload(payload)
        @viewport = normalize_viewport(@viewport.merge(@last_resize))
        emit(:resize, deep_dup(@last_resize))
        emit_change(:resize)
      end

      def handle_option_change(payload)
        @last_option_change = deep_dup(payload)
        emit(:option_change, deep_dup(payload))
      end

      def record_render_cache_clear(payload = {})
        data = normalize_hash(payload)
        source = data.fetch(:source, :addon)
        @render_cache_clears += 1
        event = event_payload(cache_event_name, count: @render_cache_clears, source: source)
        emit(cache_event_name, event)
        emit_terminal(renderer_event(cache_event_name), event)
        true
      end

      def normalize_render_payload(payload)
        data = normalize_hash(payload)
        start_row = data.fetch(:start, data.fetch("start", 0)).to_i
        end_row = data.fetch(:end, data.fetch("end", start_row)).to_i
        {
          start: start_row,
          end: end_row,
          rows: end_row >= start_row ? (start_row..end_row).to_a : []
        }
      end

      def normalize_resize_payload(payload)
        data = normalize_hash(payload)
        {
          cols: data.fetch(:cols, @terminal&.cols).to_i,
          rows: data.fetch(:rows, @terminal&.rows).to_i
        }
      end

      def viewport_payload
        measured = {
          cols: @terminal ? @terminal.cols.to_i : 0,
          rows: @terminal ? @terminal.rows.to_i : 0
        }
        normalize_viewport(measured.merge(@viewport))
      end

      def event_payload(event, **extra)
        {
          event: event,
          type: renderer_type,
          active: @active,
          context_lost: @context_lost
        }.merge(extra).compact
      end

      def emit_change(event)
        payload = event_payload(event).merge(state: state)
        emit(:change, payload)
        emit_terminal(:renderer_change, payload)
      end

      def emit_terminal(event, payload)
        @terminal&.internal&.emit(event, deep_dup(payload))
      end

      def renderer_event(event)
        :"#{renderer_type}_#{event}"
      end

      def cache_event_name
        :render_cache_clear
      end

      def default_capabilities
        return {} unless self.class.const_defined?(:DEFAULT_CAPABILITIES, false)

        deep_dup(self.class::DEFAULT_CAPABILITIES)
      end

      def normalize_options(options)
        normalize_hash(options)
      end

      def normalize_hash(value)
        return {} unless value.respond_to?(:to_h)

        value.to_h.each_with_object({}) do |(key, item), result|
          result[normalize_key(key)] = deep_dup(item)
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

      def normalize_viewport(value)
        normalize_numeric_hash(value, integer_keys: %i[cols rows width height scroll_top scroll_left])
      end

      def normalize_scrollbar(value)
        normalize_numeric_hash(value, integer_keys: %i[width position size])
      end

      def normalize_numeric_hash(value, integer_keys:)
        normalize_hash(value).each_with_object({}) do |(key, item), result|
          result[key] = if integer_keys.include?(key)
            item.to_i
          elsif key == :device_pixel_ratio || key.to_s.end_with?("_scale")
            item.to_f
          else
            deep_dup(item)
          end
        end
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
