# frozen_string_literal: true

module RTerm
  module Common
    # Constants for cell content, attribute, and color encoding.
    # These mirror the bit-packing layout from xterm.js's Constants.ts.
    module BufferConstants
      # Content word bit layout
      module Content
        CODEPOINT_MASK   = 0x1FFFFF   # bits 0-20: Unicode codepoint
        IS_COMBINED_MASK = 0x200000   # bit 21: combined/multi-codepoint string
        HAS_CONTENT_MASK = 0x3FFFFF   # bits 0-21: non-zero = has content
        WIDTH_MASK       = 0xC00000   # bits 22-23: wcwidth (0-2)
        WIDTH_SHIFT      = 22
      end

      # Color mode (bits 24-25 of fg/bg words)
      module ColorMode
        DEFAULT = 0x0000000
        P16     = 0x1000000
        P256    = 0x2000000
        RGB     = 0x3000000
        MASK    = 0x3000000
      end

      # Color component masks
      module Color
        BLUE_MASK    = 0x0000FF
        BLUE_SHIFT   = 0
        GREEN_MASK   = 0x00FF00
        GREEN_SHIFT  = 8
        RED_MASK     = 0xFF0000
        RED_SHIFT    = 16
        RGB_MASK     = 0xFFFFFF
        PCOLOR_MASK  = 0x0000FF
        PCOLOR_SHIFT = 0
      end

      # FG attribute flags (bits 26-31 of fg word)
      module FgFlags
        INVERSE       = 0x04000000 # bit 26
        BOLD          = 0x08000000 # bit 27
        UNDERLINE     = 0x10000000 # bit 28
        BLINK         = 0x20000000 # bit 29
        INVISIBLE     = 0x40000000 # bit 30
        STRIKETHROUGH = 0x80000000 # bit 31
      end

      # BG attribute flags (bits 26-30 of bg word)
      module BgFlags
        ITALIC       = 0x04000000 # bit 26
        DIM          = 0x08000000 # bit 27
        HAS_EXTENDED = 0x10000000 # bit 28
        PROTECTED    = 0x20000000 # bit 29
        OVERLINE     = 0x40000000 # bit 30
      end

      # Underline styles (3 bits in extended attrs)
      module UnderlineStyle
        NONE   = 0
        SINGLE = 1
        DOUBLE = 2
        CURLY  = 3
        DOTTED = 4
        DASHED = 5
      end

      # Default cell values
      NULL_CELL_CHAR  = ""
      NULL_CELL_WIDTH = 1
      NULL_CELL_CODE  = 0
      WHITESPACE_CELL_CHAR = " "
      WHITESPACE_CELL_CODE = 32
    end
  end
end
