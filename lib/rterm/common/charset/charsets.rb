# frozen_string_literal: true

require_relative "charset_table"

module RTerm
  module Common
    # Built-in terminal character sets.
    module Charsets
      ASCII = CharsetTable.new.freeze

      DEC_SPECIAL_GRAPHICS = CharsetTable.new(
        "`" => "◆",
        "a" => "▒",
        "b" => "␉",
        "c" => "␌",
        "d" => "␍",
        "e" => "␊",
        "f" => "°",
        "g" => "±",
        "h" => "␤",
        "i" => "␋",
        "j" => "┘",
        "k" => "┐",
        "l" => "┌",
        "m" => "└",
        "n" => "┼",
        "o" => "⎺",
        "p" => "⎻",
        "q" => "─",
        "r" => "⎼",
        "s" => "⎽",
        "t" => "├",
        "u" => "┤",
        "v" => "┴",
        "w" => "┬",
        "x" => "│",
        "y" => "≤",
        "z" => "≥",
        "{" => "π",
        "|" => "≠",
        "}" => "£",
        "~" => "·"
      ).freeze

      TABLES = {
        ascii: ASCII,
        us_ascii: ASCII,
        "B" => ASCII,
        dec_special_graphics: DEC_SPECIAL_GRAPHICS,
        line_drawing: DEC_SPECIAL_GRAPHICS,
        "0" => DEC_SPECIAL_GRAPHICS
      }.freeze

      # @param name [Symbol, String]
      # @return [CharsetTable]
      def self.fetch(name)
        TABLES.fetch(name, ASCII)
      end
    end
  end
end
