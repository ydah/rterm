# frozen_string_literal: true

require_relative "constants"

module RTerm
  module Common
    # Represents a single terminal cell with character, width, and text attributes.
    # Attributes are stored as bit-packed integers for memory efficiency,
    # following the xterm.js layout.
    class CellData
      include BufferConstants

      attr_accessor :content, :fg, :bg, :link
      attr_reader :combined_data

      def initialize
        @content = Content::WIDTH_MASK & (1 << Content::WIDTH_SHIFT) # width=1
        @fg = 0
        @bg = 0
        @link = nil
        @combined_data = nil
      end

      # --- Character ---

      # @return [String] the character stored in this cell
      def char
        return @combined_data if combined?
        return "" unless has_content?

        code = @content & Content::CODEPOINT_MASK
        code.chr(Encoding::UTF_8)
      end

      # Sets the character for this cell.
      # @param value [String]
      def char=(value)
        if value.nil? || value.empty?
          @content = (@content & Content::WIDTH_MASK)
          @combined_data = nil
        elsif value.length > 1
          self.combined_data = value
        else
          cp = value.ord
          @content = (@content & Content::WIDTH_MASK) | cp
          @combined_data = nil
        end
      end

      # Sets combined character data (multi-codepoint grapheme clusters).
      # @param value [String]
      def combined_data=(value)
        if value && !value.empty?
          @combined_data = value
          @content = (@content & Content::WIDTH_MASK) | Content::IS_COMBINED_MASK
        else
          @combined_data = nil
          @content = @content & Content::WIDTH_MASK
        end
      end

      # @return [Integer] the Unicode codepoint (0 if empty or combined)
      def code
        return 0 if combined?

        @content & Content::CODEPOINT_MASK
      end

      # @return [Boolean] whether this cell has any content
      def has_content?
        (@content & Content::HAS_CONTENT_MASK) != 0
      end

      # @return [Boolean] whether this cell contains combined characters
      def combined?
        (@content & Content::IS_COMBINED_MASK) != 0
      end

      # --- Width ---

      # @return [Integer] display width (0, 1, or 2)
      def width
        (@content & Content::WIDTH_MASK) >> Content::WIDTH_SHIFT
      end

      # @param value [Integer] display width
      def width=(value)
        @content = (@content & ~Content::WIDTH_MASK) | ((value & 0x3) << Content::WIDTH_SHIFT)
      end

      # --- Attribute Flags ---

      def bold?
        (@fg & FgFlags::BOLD) != 0
      end

      alias bold bold?

      def bold=(value)
        @fg = value ? (@fg | FgFlags::BOLD) : (@fg & ~FgFlags::BOLD)
      end

      def underline?
        (@fg & FgFlags::UNDERLINE) != 0
      end

      alias underline underline?

      def underline=(value)
        @fg = value ? (@fg | FgFlags::UNDERLINE) : (@fg & ~FgFlags::UNDERLINE)
      end

      def blink?
        (@fg & FgFlags::BLINK) != 0
      end

      alias blink blink?

      def blink=(value)
        @fg = value ? (@fg | FgFlags::BLINK) : (@fg & ~FgFlags::BLINK)
      end

      def inverse?
        (@fg & FgFlags::INVERSE) != 0
      end

      alias inverse inverse?

      def inverse=(value)
        @fg = value ? (@fg | FgFlags::INVERSE) : (@fg & ~FgFlags::INVERSE)
      end

      def invisible?
        (@fg & FgFlags::INVISIBLE) != 0
      end

      alias invisible invisible?

      def invisible=(value)
        @fg = value ? (@fg | FgFlags::INVISIBLE) : (@fg & ~FgFlags::INVISIBLE)
      end

      def strikethrough?
        (@fg & FgFlags::STRIKETHROUGH) != 0
      end

      alias strikethrough strikethrough?

      def strikethrough=(value)
        @fg = value ? (@fg | FgFlags::STRIKETHROUGH) : (@fg & ~FgFlags::STRIKETHROUGH)
      end

      # Note: italic is stored in bg word (xterm.js convention)
      def italic?
        (@bg & BgFlags::ITALIC) != 0
      end

      alias italic italic?

      def italic=(value)
        @bg = value ? (@bg | BgFlags::ITALIC) : (@bg & ~BgFlags::ITALIC)
      end

      # Note: dim is stored in bg word
      def dim?
        (@bg & BgFlags::DIM) != 0
      end

      alias dim dim?

      def dim=(value)
        @bg = value ? (@bg | BgFlags::DIM) : (@bg & ~BgFlags::DIM)
      end

      # Note: overline is stored in bg word
      def overline?
        (@bg & BgFlags::OVERLINE) != 0
      end

      alias overline overline?

      def overline=(value)
        @bg = value ? (@bg | BgFlags::OVERLINE) : (@bg & ~BgFlags::OVERLINE)
      end

      def protected?
        (@bg & BgFlags::PROTECTED) != 0
      end

      alias protected protected?

      def protected=(value)
        @bg = value ? (@bg | BgFlags::PROTECTED) : (@bg & ~BgFlags::PROTECTED)
      end

      # --- Foreground Color ---

      # @return [Symbol] :default, :p16, :p256, or :rgb
      def fg_color_mode
        case @fg & ColorMode::MASK
        when ColorMode::DEFAULT then :default
        when ColorMode::P16    then :p16
        when ColorMode::P256   then :p256
        when ColorMode::RGB    then :rgb
        end
      end

      # @return [Integer] the color value (palette index or RGB)
      def fg_color
        @fg & Color::RGB_MASK
      end

      def fg_red
        (@fg & Color::RED_MASK) >> Color::RED_SHIFT
      end

      def fg_green
        (@fg & Color::GREEN_MASK) >> Color::GREEN_SHIFT
      end

      def fg_blue
        (@fg & Color::BLUE_MASK) >> Color::BLUE_SHIFT
      end

      # Sets the foreground color.
      # @param mode [Symbol] :default, :p16, :p256, or :rgb
      # @param value [Integer] color value
      def set_fg_color(mode, value = 0)
        cm = case mode
             when :default then ColorMode::DEFAULT
             when :p16     then ColorMode::P16
             when :p256    then ColorMode::P256
             when :rgb     then ColorMode::RGB
             end
        @fg = (@fg & ~(ColorMode::MASK | Color::RGB_MASK)) | cm | (value & Color::RGB_MASK)
      end

      def reset_fg_color
        @fg = @fg & ~(ColorMode::MASK | Color::RGB_MASK)
      end

      # --- Background Color ---

      # @return [Symbol] :default, :p16, :p256, or :rgb
      def bg_color_mode
        case @bg & ColorMode::MASK
        when ColorMode::DEFAULT then :default
        when ColorMode::P16    then :p16
        when ColorMode::P256   then :p256
        when ColorMode::RGB    then :rgb
        end
      end

      # @return [Integer] the color value
      def bg_color
        @bg & Color::RGB_MASK
      end

      def bg_red
        (@bg & Color::RED_MASK) >> Color::RED_SHIFT
      end

      def bg_green
        (@bg & Color::GREEN_MASK) >> Color::GREEN_SHIFT
      end

      def bg_blue
        (@bg & Color::BLUE_MASK) >> Color::BLUE_SHIFT
      end

      # Sets the background color.
      # @param mode [Symbol] :default, :p16, :p256, or :rgb
      # @param value [Integer] color value
      def set_bg_color(mode, value = 0)
        cm = case mode
             when :default then ColorMode::DEFAULT
             when :p16     then ColorMode::P16
             when :p256    then ColorMode::P256
             when :rgb     then ColorMode::RGB
             end
        @bg = (@bg & ~(ColorMode::MASK | Color::RGB_MASK)) | cm | (value & Color::RGB_MASK)
      end

      def reset_bg_color
        @bg = @bg & ~(ColorMode::MASK | Color::RGB_MASK)
      end

      # --- Utility ---

      # Resets the cell to default values.
      def reset
        @content = 1 << Content::WIDTH_SHIFT # width=1
        @fg = 0
        @bg = 0
        @link = nil
        @combined_data = nil
      end

      # Creates a deep copy of this cell.
      # @return [CellData]
      def clone
        copy = CellData.new
        copy.fg = @fg
        copy.bg = @bg
        copy.link = duplicate_link(@link)
        copy.instance_variable_set(:@combined_data, @combined_data&.dup)
        copy.content = @content
        copy
      end

      # Copies all data from another cell.
      # @param other [CellData]
      def copy_from(other)
        @fg = other.fg
        @bg = other.bg
        @link = duplicate_link(other.link)
        @combined_data = other.combined_data&.dup
        @content = other.content
      end

      private

      def duplicate_link(value)
        value&.dup
      end
    end
  end
end
