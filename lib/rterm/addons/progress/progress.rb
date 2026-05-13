# frozen_string_literal: true

require_relative "../base"

module RTerm
  module Addon
    class Progress < Base
      include Common::EventEmitter

      STATE_NAMES = {
        0 => :none,
        1 => :normal,
        2 => :error,
        3 => :indeterminate,
        4 => :paused
      }.freeze

      STATE_CODES = {
        none: 0,
        remove: 0,
        normal: 1,
        set: 1,
        error: 2,
        indeterminate: 3,
        busy: 3,
        paused: 4,
        pause: 4,
        warning: 4
      }.freeze

      def initialize
        @state = build_state(0, 0, raw: nil)
        @disposables = []
      end

      def activate(terminal)
        super
        @disposables << terminal.parser.register_osc_handler(9) { |data| handle_osc(data) }
      end

      def state
        @state.dup
      end

      def progress
        state
      end

      def value
        @state[:value]
      end

      def state_code
        @state[:state]
      end

      def update(state, value = nil)
        progress_state = normalize_progress(state, value)
        return nil unless progress_state

        apply_progress(progress_state)
      end

      def remove
        update(0)
      end

      def set(value)
        update(1, value)
      end

      def error(value = 0)
        update(2, value)
      end

      def indeterminate
        update(3)
      end

      def pause(value = 0)
        update(4, value)
      end

      def on_change(&block)
        on(:change, &block)
      end

      def dispose
        @disposables.each(&:dispose)
        @disposables.clear
        super
      end

      alias onChange on_change
      alias stateCode state_code

      private

      def handle_osc(data)
        parts = data.to_s.split(";", -1)
        return nil unless parts.shift == "4"

        state = parse_integer(parts[0])
        value = parse_integer(parts[1])
        update(state, value)&.merge(raw: data)
      end

      def normalize_progress(state, value)
        code = progress_state_code(state)
        return nil unless STATE_NAMES.key?(code)

        amount = code.zero? ? 0 : progress_value(value)
        build_state(code, amount)
      end

      def progress_state_code(state)
        return state if state.is_a?(Integer)

        text = state.to_s
        return parse_integer(text) if text.match?(/\A-?\d+\z/)

        STATE_CODES[text.to_sym]
      end

      def progress_value(value)
        parsed = parse_integer(value)
        parsed = 0 if parsed.nil?
        [[parsed, 0].max, 100].min
      end

      def parse_integer(value)
        return nil if value.nil?
        return value if value.is_a?(Integer)

        text = value.to_s
        return nil unless text.match?(/\A-?\d+\z/)

        text.to_i
      end

      def build_state(code, value, raw: nil)
        payload = {
          state: code,
          value: value,
          name: STATE_NAMES.fetch(code)
        }
        payload[:raw] = raw if raw
        payload
      end

      def apply_progress(progress_state)
        @state = progress_state
        emit(:change, @state.dup)
        @terminal&.internal&.emit(:progress, @state.dup)
        @terminal&.internal&.emit(:progress_change, @state.dup)
        @state.dup
      end
    end
  end
end
