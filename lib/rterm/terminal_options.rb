# frozen_string_literal: true

module RTerm
  # Immutable-ish option bag for terminal configuration.
  class TerminalOptions
    DEFAULTS = {
      cols: 80,
      rows: 24,
      scrollback: 1000,
      tab_stop_width: 8,
      cursor_blink: false,
      cursor_style: :block,
      cursor_width: 1,
      cursor_inactive_style: :outline,
      allow_proposed_api: false,
      allow_transparency: false,
      disable_stdin: false,
      draw_bold_text_in_bright_colors: true,
      fast_scroll_modifier: :alt,
      fast_scroll_sensitivity: 5,
      font_family: "courier-new",
      font_size: 13,
      font_weight: :normal,
      font_weight_bold: :bold,
      letter_spacing: 0,
      line_height: 1.0,
      log_level: :info,
      mac_option_is_meta: false,
      mac_option_click_forces_selection: false,
      minimum_contrast_ratio: 1,
      convert_eol: false,
      clipboard_enabled: true,
      clipboard_max_bytes: 1_048_576,
      clipboard_read_handler: nil,
      clipboard_write_handler: nil,
      scroll_on_user_input: true,
      scroll_sensitivity: 1,
      screen_reader_mode: false,
      smooth_scroll_duration: 0,
      right_click_selects_word: false,
      window_options: {},
      windows_mode: false,
      word_separator: " ()[]{}'\"",
      override_colors: nil
    }.freeze

    DEFAULTS.each_key do |name|
      define_method(name) { @values[name] }
    end

    # @param overrides [Hash, TerminalOptions]
    def initialize(overrides = {})
      overrides = overrides.to_h if overrides.respond_to?(:to_h)
      unknown = overrides.keys.map(&:to_sym) - DEFAULTS.keys
      raise ArgumentError, "Unknown terminal option(s): #{unknown.join(', ')}" unless unknown.empty?

      @values = deep_dup(DEFAULTS).merge(deep_dup(symbolize_keys(overrides)))
    end

    # @param key [Symbol, String]
    # @return [Object]
    def [](key)
      @values[key.to_sym]
    end

    # @return [Hash]
    def to_h
      deep_dup(@values)
    end

    # @param overrides [Hash]
    # @return [TerminalOptions]
    def merge(overrides)
      self.class.new(to_h.merge(overrides))
    end

    private

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value
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
