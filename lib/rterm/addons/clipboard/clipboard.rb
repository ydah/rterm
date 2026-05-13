# frozen_string_literal: true

require_relative "../base"

module RTerm
  module Addon
    class Clipboard < Base
      include Common::EventEmitter

      DEFAULT_SELECTION = "clipboard"
      SELECTION_ALIASES = {
        "c" => "clipboard",
        "p" => "primary",
        "q" => "secondary",
        "s" => "select"
      }.freeze

      def initialize(read: nil, write: nil)
        @read_handler = read
        @write_handler = write
        @store = {}
        @disposables = []
      end

      attr_reader :store

      def activate(terminal)
        super
        @disposables << terminal.on(:clipboard) { |payload| handle_clipboard(payload) }
        @disposables << terminal.on(:clipboard_request) { |payload| handle_clipboard_request(payload) }
      end

      def write_text(text, selection: DEFAULT_SELECTION)
        ensure_active!

        @terminal.internal.input_handler.copy_to_clipboard(text.to_s, selection_name(selection))
      end

      def read_text(selection: DEFAULT_SELECTION)
        key = selection_name(selection)
        value = @store[key]
        return value unless value.nil?

        external_read(key)
      end

      def copy_selection(selection: DEFAULT_SELECTION)
        ensure_active!

        text = @terminal.get_selection
        write_text(text, selection: selection)
        text
      end

      def paste(text = nil, selection: DEFAULT_SELECTION)
        ensure_active!

        value = text.nil? ? read_text(selection: selection) : text.to_s
        return nil if value.nil?

        @terminal.paste(value)
      end

      def clear(selection = nil)
        if selection
          @store.delete(selection_name(selection))
        else
          @store.clear
        end
        true
      end

      def on_change(&block)
        on(:change, &block)
      end

      def dispose
        @disposables.each(&:dispose)
        @disposables.clear
        super
      end

      alias writeText write_text
      alias readText read_text
      alias copySelection copy_selection
      alias onChange on_change

      private

      def ensure_active!
        raise RuntimeError, "Clipboard addon is not active" unless @terminal
      end

      def handle_clipboard(payload)
        return unless payload[:allowed]

        text = payload[:decoded].to_s
        Array(payload[:selections]).each { |selection| @store[selection.to_s] = text }
        external_write(payload, text)
        emit(:change, payload.merge(text: text))
      end

      def handle_clipboard_request(payload)
        Array(payload[:selections]).each do |selection|
          key = selection.to_s
          next if @store.key?(key)

          value = external_read(key)
          @store[key] = value unless value.nil?
        end
      end

      def external_read(selection)
        return unless @read_handler.respond_to?(:call)

        invoke_with_selection(@read_handler, selection)
      end

      def external_write(payload, text)
        return unless @write_handler.respond_to?(:call)

        if @write_handler.arity == 1
          @write_handler.call(text)
        else
          @write_handler.call(text, payload)
        end
      end

      def invoke_with_selection(handler, selection)
        return handler.call if handler.arity.zero?
        return handler.call(selection) if handler.arity == 1 || handler.arity.negative?

        handler.call(selection, self)
      end

      def selection_name(selection)
        key = selection.to_s
        return DEFAULT_SELECTION if key.empty?
        return "cut#{key}" if key.match?(/\A[0-7]\z/)

        SELECTION_ALIASES.fetch(key, key)
      end
    end
  end
end
