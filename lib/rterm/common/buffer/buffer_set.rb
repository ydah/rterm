# frozen_string_literal: true

require_relative "buffer"

module RTerm
  module Common
    # Manages the normal and alternate screen buffers.
    # Provides switching between them (used by DECSET 47/1047/1049).
    class BufferSet
      attr_reader :normal, :alt, :active

      # @param cols [Integer] number of columns
      # @param rows [Integer] number of rows
      # @param scrollback [Integer] number of scrollback lines (normal buffer only)
      def initialize(cols, rows, scrollback = 1000)
        @normal = Buffer.new(cols, rows, scrollback)
        @alt = Buffer.new(cols, rows, 0)
        @active = @normal
      end

      # Switches to the alternate screen buffer.
      def activate_alt_buffer(clear: false)
        @alt.clear if clear
        @active = @alt
      end

      # Switches back to the normal screen buffer.
      def activate_normal_buffer
        @active = @normal
      end
    end
  end
end
