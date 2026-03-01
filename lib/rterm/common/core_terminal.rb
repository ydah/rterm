# frozen_string_literal: true

require_relative "event_emitter"
require_relative "buffer/buffer_set"
require_relative "parser/escape_sequence_parser"
require_relative "input/input_handler"
require_relative "unicode/unicode_handler"

module RTerm
  module Common
    # Core terminal implementation that wires together the parser,
    # input handler, and buffer system. This is the central engine
    # for terminal emulation, independent of any rendering.
    class CoreTerminal
      include EventEmitter

      attr_reader :cols, :rows, :buffer_set, :parser, :input_handler, :unicode_handler

      # @param options [Hash] terminal options
      # @option options [Integer] :cols (80) number of columns
      # @option options [Integer] :rows (24) number of rows
      # @option options [Integer] :scrollback (1000) scrollback buffer size
      def initialize(options = {})
        @cols = options.fetch(:cols, 80)
        @rows = options.fetch(:rows, 24)
        @scrollback = options.fetch(:scrollback, 1000)

        @unicode_handler = UnicodeHandler.new
        @buffer_set = BufferSet.new(@cols, @rows, @scrollback)
        @parser = EscapeSequenceParser.new
        @input_handler = InputHandler.new(@buffer_set, @parser, options)

        wire_events
      end

      # Writes data to the terminal (from PTY or other source).
      # The data is parsed and applied to the buffer.
      # @param data [String] the data to write
      def write(data)
        @parser.parse(data)
        emit(:write_parsed)
      end

      # Writes data followed by a newline.
      # @param data [String] the data to write
      def writeln(data)
        write("#{data}\r\n")
      end

      # Resizes the terminal.
      # @param cols [Integer] new number of columns
      # @param rows [Integer] new number of rows
      def resize(cols, rows)
        return if cols == @cols && rows == @rows

        @cols = cols
        @rows = rows
        @buffer_set.normal.resize(cols, rows)
        @buffer_set.alt.resize(cols, rows)
        emit(:resize, { cols: cols, rows: rows })
      end

      # Resets the terminal to its initial state.
      def reset
        @parser.reset
        @buffer_set.normal.clear
        @buffer_set.alt.clear
        @buffer_set.activate_normal_buffer
        @input_handler.send(:full_reset) if @input_handler.respond_to?(:full_reset, true)
        emit(:reset)
      end

      private

      def wire_events
        # Forward input handler events
        @input_handler.on(:bell) { emit(:bell) }
        @input_handler.on(:title_change) { |title| emit(:title_change, title) }
        @input_handler.on(:cursor_move) { emit(:cursor_move) }
        @input_handler.on(:line_feed) { emit(:line_feed) }
        @input_handler.on(:data) { |data| emit(:data, data) }
      end
    end
  end
end
