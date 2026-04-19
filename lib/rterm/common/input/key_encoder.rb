# frozen_string_literal: true

module RTerm
  module Common
    # Encodes high-level key events into terminal input sequences.
    class KeyEncoder
      ARROWS = {
        up: "A",
        down: "B",
        right: "C",
        left: "D"
      }.freeze

      SS3_ARROWS = {
        up: "A",
        down: "B",
        right: "C",
        left: "D"
      }.freeze

      NAVIGATION = {
        home: ["H", :cursor],
        end: ["F", :cursor],
        insert: [2, :tilde],
        delete: [3, :tilde],
        page_up: [5, :tilde],
        page_down: [6, :tilde]
      }.freeze

      FUNCTION_KEYS = {
        f1: ["P", :ss3],
        f2: ["Q", :ss3],
        f3: ["R", :ss3],
        f4: ["S", :ss3],
        f5: [15, :tilde],
        f6: [17, :tilde],
        f7: [18, :tilde],
        f8: [19, :tilde],
        f9: [20, :tilde],
        f10: [21, :tilde],
        f11: [23, :tilde],
        f12: [24, :tilde]
      }.freeze

      CONTROL_KEYS = {
        backspace: "\x7F",
        tab: "\t",
        enter: "\r",
        escape: "\e"
      }.freeze

      KEYPAD_APPLICATION = {
        keypad_enter: "\eOM",
        keypad_add: "\eOk",
        keypad_subtract: "\eOm",
        keypad_multiply: "\eOj",
        keypad_divide: "\eOo",
        keypad_decimal: "\eOn",
        keypad_0: "\eOp",
        keypad_1: "\eOq",
        keypad_2: "\eOr",
        keypad_3: "\eOs",
        keypad_4: "\eOt",
        keypad_5: "\eOu",
        keypad_6: "\eOv",
        keypad_7: "\eOw",
        keypad_8: "\eOx",
        keypad_9: "\eOy"
      }.freeze

      KEYPAD_NUMERIC = {
        keypad_enter: "\r",
        keypad_add: "+",
        keypad_subtract: "-",
        keypad_multiply: "*",
        keypad_divide: "/",
        keypad_decimal: ".",
        keypad_0: "0",
        keypad_1: "1",
        keypad_2: "2",
        keypad_3: "3",
        keypad_4: "4",
        keypad_5: "5",
        keypad_6: "6",
        keypad_7: "7",
        keypad_8: "8",
        keypad_9: "9"
      }.freeze

      def initialize(modes = {})
        @modes = modes
      end

      # @param key [Symbol, String]
      # @param modifiers [Array<Symbol>]
      # @param text [String, nil]
      # @return [String, nil]
      def encode(key, modifiers: [], text: nil)
        normalized = normalize_key(key)
        modifier_value = csi_modifier(modifiers)
        return encode_text(text, modifiers) if text
        return encode_control(normalized, modifiers) if CONTROL_KEYS.key?(normalized)
        return encode_arrow(normalized, modifier_value) if ARROWS.key?(normalized)
        return encode_navigation(normalized, modifier_value) if NAVIGATION.key?(normalized)
        return encode_function_key(normalized, modifier_value) if FUNCTION_KEYS.key?(normalized)
        return encode_keypad(normalized, modifiers) if KEYPAD_NUMERIC.key?(normalized)

        encode_literal_key(key, modifiers)
      end

      private

      def normalize_key(key)
        key.to_s.downcase.tr("-", "_").to_sym
      end

      def encode_text(text, modifiers)
        value = text.to_s
        return value unless modifiers.map(&:to_sym).include?(:alt) || modifiers.map(&:to_sym).include?(:meta)

        "\e#{value}"
      end

      def encode_control(key, modifiers)
        value = CONTROL_KEYS[key]
        return "\e#{value}" if key == :tab && modifiers.map(&:to_sym).include?(:alt)

        value
      end

      def encode_arrow(key, modifier_value)
        final = ARROWS[key]
        return "\eO#{SS3_ARROWS[key]}" if application_cursor? && modifier_value == 1
        return "\e[#{final}" if modifier_value == 1

        "\e[1;#{modifier_value}#{final}"
      end

      def encode_navigation(key, modifier_value)
        code, type = NAVIGATION[key]
        if type == :cursor
          return "\eO#{code}" if application_cursor? && modifier_value == 1
          return "\e[#{code}" if modifier_value == 1

          return "\e[1;#{modifier_value}#{code}"
        end

        modifier_value == 1 ? "\e[#{code}~" : "\e[#{code};#{modifier_value}~"
      end

      def encode_function_key(key, modifier_value)
        code, type = FUNCTION_KEYS[key]
        if type == :ss3
          return "\eO#{code}" if modifier_value == 1

          return "\e[1;#{modifier_value}#{code}"
        end

        modifier_value == 1 ? "\e[#{code}~" : "\e[#{code};#{modifier_value}~"
      end

      def encode_keypad(key, modifiers)
        value = application_keypad? ? KEYPAD_APPLICATION[key] : KEYPAD_NUMERIC[key]
        modifiers.map(&:to_sym).include?(:alt) ? "\e#{value}" : value
      end

      def encode_literal_key(key, modifiers)
        value = key.to_s
        return nil if value.empty?
        return control_character(value) if modifiers.map(&:to_sym).include?(:ctrl)
        return "\e#{value}" if modifiers.map(&:to_sym).include?(:alt) || modifiers.map(&:to_sym).include?(:meta)

        value
      end

      def control_character(value)
        char = value.downcase[0]
        return nil unless char&.match?(/[a-z]/)

        (char.ord - 96).chr
      end

      def csi_modifier(modifiers)
        symbols = modifiers.map(&:to_sym)
        value = 1
        value += 1 if symbols.include?(:shift)
        value += 2 if symbols.include?(:alt) || symbols.include?(:meta)
        value += 4 if symbols.include?(:ctrl)
        value
      end

      def application_cursor?
        @modes[:application_cursor_keys_mode] == true
      end

      def application_keypad?
        @modes[:application_keypad_mode] == true
      end
    end
  end
end
