# frozen_string_literal: true

module RTerm
  # Terminal color theme compatible with xterm.js theme keys.
  class Theme
    DEFAULTS = {
      foreground: "#ffffff",
      background: "#000000",
      cursor: "#ffffff",
      cursor_accent: "#000000",
      selection_foreground: nil,
      selection_background: "#ffffff40",
      black: "#000000",
      red: "#cd3131",
      green: "#0dbc79",
      yellow: "#e5e510",
      blue: "#2472c8",
      magenta: "#bc3fbc",
      cyan: "#11a8cd",
      white: "#e5e5e5",
      bright_black: "#666666",
      bright_red: "#f14c4c",
      bright_green: "#23d18b",
      bright_yellow: "#f5f543",
      bright_blue: "#3b8eea",
      bright_magenta: "#d670d6",
      bright_cyan: "#29b8db",
      bright_white: "#ffffff",
      extended_ansi: nil
    }.freeze

    DEFAULTS.each_key do |name|
      attr_accessor name
    end

    # @param overrides [Hash]
    def initialize(overrides = {})
      unknown = overrides.keys.map(&:to_sym) - DEFAULTS.keys
      raise ArgumentError, "Unknown theme color(s): #{unknown.join(', ')}" unless unknown.empty?

      DEFAULTS.merge(symbolize_keys(overrides)).each do |key, value|
        public_send("#{key}=", duplicate(value))
      end
    end

    # @return [Hash]
    def to_h
      DEFAULTS.each_key.each_with_object({}) do |key, result|
        result[key] = duplicate(public_send(key))
      end
    end

    private

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value
      end
    end

    def duplicate(value)
      case value
      when Array then value.map { |item| duplicate(item) }
      when Hash then value.transform_values { |item| duplicate(item) }
      else value
      end
    end
  end
end
