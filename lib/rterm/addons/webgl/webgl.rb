# frozen_string_literal: true

require_relative "../base"

module RTerm
  module Addon
    class WebGL < Base
      include Common::EventEmitter

      DEFAULT_CAPABILITIES = {
        accelerated: true,
        context_type: "webgl2",
        texture_atlas: true
      }.freeze

      attr_reader :renderer, :context

      def initialize(options = {})
        @options = normalize_options(options)
        @renderer = @options[:renderer]
        @context = @options[:context]
        @capabilities = DEFAULT_CAPABILITIES.merge(normalize_hash(@options.fetch(:capabilities, {})))
        @disposables = []
        @active = false
        @context_lost = false
        @last_render = nil
        @last_resize = nil
        @last_option_change = nil
        @texture_atlas_clears = 0
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
        :webgl
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
          last_render: deep_dup(@last_render),
          last_resize: deep_dup(@last_resize),
          last_option_change: deep_dup(@last_option_change),
          texture_atlas_clears: @texture_atlas_clears
        }
      end

      def last_render
        deep_dup(@last_render)
      end

      def last_resize
        deep_dup(@last_resize)
      end

      def attach_renderer(renderer, context: @context, capabilities: nil)
        @renderer = renderer
        @context = context
        @capabilities = @capabilities.merge(normalize_hash(capabilities)) if capabilities
        emit_change(:attach_renderer)
        state
      end

      def lose_context(reason = nil)
        return false if @context_lost

        @context_lost = true
        payload = event_payload(:context_loss, reason: reason)
        emit(:context_loss, payload)
        emit_terminal(:webgl_context_loss, payload)
        emit_change(:context_loss)
        true
      end

      def restore_context(context = nil)
        return false unless @context_lost

        @context = context unless context.nil?
        @context_lost = false
        payload = event_payload(:context_restore)
        emit(:context_restore, payload)
        emit_terminal(:webgl_context_restore, payload)
        emit_change(:context_restore)
        @terminal&.refresh(0, @terminal.rows - 1)
        true
      end

      def clear_texture_atlas
        return record_texture_atlas_clear({ source: :addon }) unless @terminal

        @terminal.clear_texture_atlas
      end

      def on_context_loss(&block)
        on(:context_loss, &block)
      end

      def on_context_restore(&block)
        on(:context_restore, &block)
      end

      def on_texture_atlas_clear(&block)
        on(:texture_atlas_clear, &block)
      end

      def on_change(&block)
        on(:change, &block)
      end

      alias active active?
      alias is_context_lost context_lost?
      alias isContextLost context_lost?
      alias rendererType renderer_type
      alias lastRender last_render
      alias lastResize last_resize
      alias attachRenderer attach_renderer
      alias loseContext lose_context
      alias restoreContext restore_context
      alias clearTextureAtlas clear_texture_atlas
      alias onContextLoss on_context_loss
      alias onContextRestore on_context_restore
      alias onTextureAtlasClear on_texture_atlas_clear
      alias onChange on_change

      private

      def subscribe_terminal_events
        @disposables << @terminal.on(:render) { |payload| handle_render(payload) }
        @disposables << @terminal.on(:resize) { |payload| handle_resize(payload) }
        @disposables << @terminal.on(:option_change) { |payload| handle_option_change(payload) }
        @disposables << @terminal.on(:texture_atlas_clear) { |payload| record_texture_atlas_clear(payload) }
      end

      def handle_render(payload)
        @last_render = normalize_render_payload(payload)
        emit(:render, deep_dup(@last_render))
      end

      def handle_resize(payload)
        @last_resize = normalize_resize_payload(payload)
        emit(:resize, deep_dup(@last_resize))
        emit_change(:resize)
      end

      def handle_option_change(payload)
        @last_option_change = deep_dup(payload)
        emit(:option_change, deep_dup(payload))
      end

      def record_texture_atlas_clear(payload = {})
        data = normalize_hash(payload)
        source = data.fetch(:source, :addon)
        @texture_atlas_clears += 1
        event = event_payload(:texture_atlas_clear, count: @texture_atlas_clears, source: source)
        emit(:texture_atlas_clear, event)
        emit_terminal(:webgl_texture_atlas_clear, event)
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
        {
          cols: @terminal ? @terminal.cols.to_i : 0,
          rows: @terminal ? @terminal.rows.to_i : 0
        }
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
