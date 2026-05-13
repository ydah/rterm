# frozen_string_literal: true

require_relative "buffer"
require_relative "../event_emitter"

module RTerm
  module Common
    # Manages the normal and alternate screen buffers.
    # Provides switching between them (used by DECSET 47/1047/1049).
    class BufferSet
      include EventEmitter

      attr_reader :normal, :alt, :active

      # @param cols [Integer] number of columns
      # @param rows [Integer] number of rows
      # @param scrollback [Integer] number of scrollback lines (normal buffer only)
      def initialize(cols, rows, scrollback = 1000)
        @normal = Buffer.new(cols, rows, scrollback, :normal)
        @alt = Buffer.new(cols, rows, 0, :alternate)
        @active = @normal
      end

      # Switches to the alternate screen buffer.
      def activate_alt_buffer(clear: false)
        previous = @active
        @alt.clear if clear
        @active = @alt
        emit(:buffer_change, active: @active, old_active: previous)
      end

      # Switches back to the normal screen buffer.
      def activate_normal_buffer
        previous = @active
        @active = @normal
        emit(:buffer_change, active: @active, old_active: previous)
      end
    end
  end
end
