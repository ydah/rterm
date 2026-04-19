# frozen_string_literal: true

require_relative "parser_state"
require_relative "params"

module RTerm
  module Common
    # ANSI/VT escape sequence parser based on a state machine.
    # Faithfully implements the xterm.js VT500 transition table.
    class EscapeSequenceParser
      include ParserState
      include ParserAction

      INDEX_STATE_SHIFT       = 8
      TRANSITION_ACTION_SHIFT = 8
      TRANSITION_STATE_MASK   = 0xFF
      NON_ASCII_PRINTABLE     = 0xA0
      TABLE_SIZE              = 4096

      # @param table [Array<Integer>, nil] custom transition table (for testing)
      def initialize(table = nil)
        @table = table || self.class.build_vt500_transition_table
        @current_state = GROUND
        @params = Params.new
        @collect = 0

        # Handler storage
        @print_handler = nil
        @execute_handlers = {}
        @csi_handlers = {}
        @esc_handlers = {}
        @osc_handlers = {}
        @dcs_handlers = {}
        @apc_handlers = []
        @pm_handlers = []
        @sos_handlers = []

        # Fallback handlers
        @print_handler_fb = nil
        @execute_handler_fb = nil
        @csi_handler_fb = nil
        @esc_handler_fb = nil

        # OSC/DCS state
        @osc_data = +""
        @osc_id = -1
        @dcs_data = +""
        @apc_data = +""
        @sos_pm_data = +""
        @sos_pm_kind = nil
      end

      # --- Handler Registration ---

      # Sets the handler for printable characters.
      # @yield [String] the printable character(s)
      def set_print_handler(&handler)
        @print_handler = handler
      end

      # Sets a handler for a C0/C1 control character.
      # @param code [Integer] the character code (e.g., 0x07 for BEL)
      # @yield called when the control character is encountered
      def set_execute_handler(code, &handler)
        @execute_handlers[code] = handler
      end

      # Registers a CSI sequence handler.
      # @param id [Hash] :prefix, :intermediates, :final
      # @yield [Params] the parsed parameters
      # @return [Disposable]
      def set_csi_handler(id, &handler)
        ident = self.class.identifier(id)
        @csi_handlers[ident] ||= []
        @csi_handlers[ident] << handler
        Disposable.new { @csi_handlers[ident]&.delete(handler) }
      end

      # Registers an ESC sequence handler.
      # @param id [Hash] :intermediates, :final
      # @yield called when the sequence is encountered
      # @return [Disposable]
      def set_esc_handler(id, &handler)
        ident = self.class.identifier(id)
        @esc_handlers[ident] ||= []
        @esc_handlers[ident] << handler
        Disposable.new { @esc_handlers[ident]&.delete(handler) }
      end

      # Registers an OSC sequence handler.
      # @param id [Integer] the OSC identifier (e.g., 0 for title)
      # @yield [String] the OSC data string
      def set_osc_handler(id, &handler)
        @osc_handlers[id] ||= []
        @osc_handlers[id] << handler
        Disposable.new { @osc_handlers[id]&.delete(handler) }
      end

      # Registers a DCS sequence handler.
      # @param id [Hash] :prefix, :intermediates, :final
      # @yield [String] the DCS data string
      def set_dcs_handler(id, &handler)
        ident = self.class.identifier(id)
        @dcs_handlers[ident] ||= []
        @dcs_handlers[ident] << handler
        Disposable.new { @dcs_handlers[ident]&.delete(handler) }
      end

      # Registers an APC string handler.
      # @yield [String] the APC payload
      # @return [Disposable]
      def set_apc_handler(&handler)
        @apc_handlers << handler
        Disposable.new { @apc_handlers.delete(handler) }
      end

      # Registers a PM string handler.
      # @yield [String] the PM payload
      # @return [Disposable]
      def set_pm_handler(&handler)
        @pm_handlers << handler
        Disposable.new { @pm_handlers.delete(handler) }
      end

      # Registers a SOS string handler.
      # @yield [String] the SOS payload
      # @return [Disposable]
      def set_sos_handler(&handler)
        @sos_handlers << handler
        Disposable.new { @sos_handlers.delete(handler) }
      end

      # --- Parsing ---

      # Parses input data through the state machine.
      # @param data [String] the raw input data
      def parse(data)
        codepoints = data.encode(Encoding::UTF_8).codepoints
        length = codepoints.length
        i = 0

        while i < length
          code = codepoints[i]
          lookup = code < NON_ASCII_PRINTABLE ? code : NON_ASCII_PRINTABLE
          transition = @table[(@current_state << INDEX_STATE_SHIFT) | lookup]
          action = transition >> TRANSITION_ACTION_SHIFT
          next_state = transition & TRANSITION_STATE_MASK

          case action
          when ParserAction::PRINT
            # Read-ahead for consecutive printable chars
            start_pos = i
            i += 1
            while i < length
              c = codepoints[i]
              break if c < 0x20 || (c > 0x7E && c < NON_ASCII_PRINTABLE)

              i += 1
            end
            @print_handler&.call(codepoints[start_pos...i].pack("U*"))
            i -= 1

          when ParserAction::EXECUTE
            handler = @execute_handlers[code]
            handler&.call

          when ParserAction::IGNORE
            # nothing

          when ParserAction::ERROR
            @current_state = GROUND
            next_state = GROUND

          when ParserAction::CSI_DISPATCH
            ident = (@collect << 8) | code
            handlers = @csi_handlers[ident]
            handled = false
            if handlers
              (handlers.length - 1).downto(0) do |j|
                result = handlers[j].call(@params)
                if result == true
                  handled = true
                  break
                end
              end
            end
            @csi_handler_fb&.call(ident, @params) unless handled

          when ParserAction::PARAM
            # Read-ahead for parameter characters
            loop do
              case code
              when 0x3B # ';'
                @params.add_param(0)
              when 0x3A # ':'
                @params.add_sub_param(-1)
              else # 0x30..0x39 digits
                @params.add_digit(code - 48)
              end
              i += 1
              break if i >= length

              code = codepoints[i]
              break unless code > 0x2F && code < 0x3C
            end
            i -= 1

          when ParserAction::COLLECT
            @collect = (@collect << 8) | code

          when ParserAction::ESC_DISPATCH
            ident = (@collect << 8) | code
            handlers = @esc_handlers[ident]
            handled = false
            if handlers
              (handlers.length - 1).downto(0) do |j|
                result = handlers[j].call
                if result == true
                  handled = true
                  break
                end
              end
            end
            @esc_handler_fb&.call(ident) unless handled

          when ParserAction::CLEAR
            @params.reset
            @params.add_param(0)
            @collect = 0

          when ParserAction::OSC_START
            @osc_data = +""
            @osc_id = -1

          when ParserAction::OSC_PUT
            # Read-ahead for OSC data — break on all C0/C1 controls
            start_pos = i
            i += 1
            while i < length
              c = codepoints[i]
              break if c < 0x20
              break if c >= 0x7F && c < NON_ASCII_PRINTABLE

              i += 1
            end
            chunk = codepoints[start_pos...i].pack("U*")
            if @osc_id == -1
              # Parse OSC id from the beginning
              semicolon_idx = chunk.index(";")
              if semicolon_idx
                @osc_id = chunk[0...semicolon_idx].to_i
                @osc_data << chunk[(semicolon_idx + 1)..]
              else
                @osc_data << chunk
              end
            else
              @osc_data << chunk
            end
            i -= 1

          when ParserAction::OSC_END
            dispatch_osc(code)
            # Handle ST (ESC \) — if code is ESC, we need to stay in ESCAPE
            next_state = ESCAPE if code == 0x1B

          when ParserAction::DCS_HOOK
            ident = (@collect << 8) | code
            @dcs_ident = ident
            @dcs_data = +""

          when ParserAction::DCS_PUT
            start_pos = i
            i += 1
            while i < length
              c = codepoints[i]
              break if c == 0x18 || c == 0x1A || c == 0x1B || (c >= 0x7F && c < NON_ASCII_PRINTABLE)

              i += 1
            end
            @dcs_data << codepoints[start_pos...i].pack("U*")
            i -= 1

          when ParserAction::DCS_UNHOOK
            dispatch_dcs

          when ParserAction::APC_START
            @apc_data = +""

          when ParserAction::APC_PUT
            start_pos = i
            i += 1
            while i < length
              c = codepoints[i]
              break if c < 0x20 || (c >= 0x7F && c < NON_ASCII_PRINTABLE)

              i += 1
            end
            @apc_data << codepoints[start_pos...i].pack("U*")
            i -= 1

          when ParserAction::SOS_START
            @sos_pm_kind = :sos
            @sos_pm_data = +""

          when ParserAction::PM_START
            @sos_pm_kind = :pm
            @sos_pm_data = +""

          when ParserAction::SOS_PM_PUT
            start_pos = i
            i += 1
            while i < length
              c = codepoints[i]
              break if c < 0x20 || (c >= 0x7F && c < NON_ASCII_PRINTABLE)

              i += 1
            end
            @sos_pm_data << codepoints[start_pos...i].pack("U*")
            i -= 1
          end

          # Dispatch pending string controls when leaving those states.
          if @current_state == OSC_STRING && next_state != OSC_STRING && action != ParserAction::OSC_END
            dispatch_osc(code)
          end

          if @current_state == DCS_PASSTHROUGH && next_state != DCS_PASSTHROUGH &&
             action != ParserAction::DCS_UNHOOK
            dispatch_dcs
          end

          dispatch_apc if @current_state == APC_STRING && next_state != APC_STRING

          dispatch_sos_pm if @current_state == SOS_PM_STRING && next_state != SOS_PM_STRING

          @current_state = next_state
          i += 1
        end
      end

      # Resets the parser to initial state.
      def reset
        @current_state = GROUND
        @params.reset
        @collect = 0
        @osc_data = +""
        @osc_id = -1
        @dcs_data = +""
        @apc_data = +""
        @sos_pm_data = +""
        @sos_pm_kind = nil
      end

      # @return [Integer] the current parser state
      def current_state
        @current_state
      end

      private

      def dispatch_osc(_code)
        # Try to parse OSC id if not yet parsed
        if @osc_id == -1
          semicolon_idx = @osc_data.index(";")
          if semicolon_idx
            @osc_id = @osc_data[0...semicolon_idx].to_i
            @osc_data = @osc_data[(semicolon_idx + 1)..]
          end
        end

        handlers = @osc_handlers[@osc_id]
        return unless handlers

        (handlers.length - 1).downto(0) do |j|
          handlers[j].call(@osc_data)
        end
      end

      def dispatch_dcs
        handlers = @dcs_handlers[@dcs_ident]
        return unless handlers

        (handlers.length - 1).downto(0) do |j|
          handlers[j].call(@dcs_data, @params)
        end
      end

      def dispatch_apc
        (@apc_handlers.length - 1).downto(0) do |j|
          @apc_handlers[j].call(@apc_data)
        end
      end

      def dispatch_sos_pm
        handlers = @sos_pm_kind == :pm ? @pm_handlers : @sos_handlers
        (handlers.length - 1).downto(0) do |j|
          handlers[j].call(@sos_pm_data)
        end
      end

      # --- Class Methods ---

      # Builds an identifier integer from a handler id hash.
      # @param id [Hash] :prefix, :intermediates, :final
      # @return [Integer]
      def self.identifier(id)
        res = 0
        if id[:prefix]
          res = id[:prefix].is_a?(Integer) ? id[:prefix] : id[:prefix].ord
        end
        if id[:intermediates]
          id[:intermediates].each_byte do |b|
            res = (res << 8) | b
          end
        end
        final = id[:final]
        res = (res << 8) | (final.is_a?(Integer) ? final : final.ord)
        res
      end

      # Builds the VT500 transition table.
      # @return [Array<Integer>]
      def self.build_vt500_transition_table
        table = Array.new(TABLE_SIZE, 0)

        # Helper to set transitions
        set = lambda do |state, code_or_range, action, next_state|
          codes = code_or_range.is_a?(Range) ? code_or_range : [code_or_range]
          codes.each do |code|
            table[(state << INDEX_STATE_SHIFT) | code] = (action << TRANSITION_ACTION_SHIFT) | next_state
          end
        end

        # Default: ERROR → GROUND for all states
        ParserState::STATE_LENGTH.times do |state|
          256.times do |code|
            table[(state << INDEX_STATE_SHIFT) | code] = (ParserAction::ERROR << TRANSITION_ACTION_SHIFT) | GROUND
          end
        end

        executables = (0x00..0x17).to_a + [0x19] + (0x1C..0x1F).to_a

        # --- Anywhere rules (apply to ALL states) ---
        ParserState::STATE_LENGTH.times do |state|
          set.call(state, 0x18, ParserAction::EXECUTE, GROUND)
          set.call(state, 0x1A, ParserAction::EXECUTE, GROUND)
          set.call(state, 0x1B, ParserAction::CLEAR, ESCAPE)
          (0x80..0x8F).each { |c| set.call(state, c, ParserAction::EXECUTE, GROUND) }
          set.call(state, 0x90, ParserAction::CLEAR, DCS_ENTRY)
          (0x91..0x97).each { |c| set.call(state, c, ParserAction::EXECUTE, GROUND) }
          set.call(state, 0x98, ParserAction::SOS_START, SOS_PM_STRING)
          set.call(state, 0x99, ParserAction::EXECUTE, GROUND)
          set.call(state, 0x9A, ParserAction::EXECUTE, GROUND)
          set.call(state, 0x9B, ParserAction::CLEAR, CSI_ENTRY)
          set.call(state, 0x9C, ParserAction::IGNORE, GROUND)
          set.call(state, 0x9D, ParserAction::OSC_START, OSC_STRING)
          set.call(state, 0x9E, ParserAction::PM_START, SOS_PM_STRING)
          set.call(state, 0x9F, ParserAction::APC_START, APC_STRING)
        end

        # --- GROUND ---
        (0x20..0x7E).each { |c| set.call(GROUND, c, ParserAction::PRINT, GROUND) }
        executables.each { |c| set.call(GROUND, c, ParserAction::EXECUTE, GROUND) }
        set.call(GROUND, NON_ASCII_PRINTABLE, ParserAction::PRINT, GROUND)

        # --- ESCAPE ---
        executables.each { |c| set.call(ESCAPE, c, ParserAction::EXECUTE, ESCAPE) }
        set.call(ESCAPE, 0x7F, ParserAction::IGNORE, ESCAPE)
        set.call(ESCAPE, 0x5B, ParserAction::CLEAR, CSI_ENTRY)       # '['
        set.call(ESCAPE, 0x5D, ParserAction::OSC_START, OSC_STRING)  # ']'
        set.call(ESCAPE, 0x50, ParserAction::CLEAR, DCS_ENTRY)       # 'P'
        set.call(ESCAPE, 0x58, ParserAction::SOS_START, SOS_PM_STRING)  # 'X'
        set.call(ESCAPE, 0x5E, ParserAction::PM_START, SOS_PM_STRING)   # '^'
        set.call(ESCAPE, 0x5F, ParserAction::APC_START, APC_STRING)  # '_'
        (0x20..0x2F).each { |c| set.call(ESCAPE, c, ParserAction::COLLECT, ESCAPE_INTERMEDIATE) }
        (0x30..0x4F).each { |c| set.call(ESCAPE, c, ParserAction::ESC_DISPATCH, GROUND) }
        (0x51..0x57).each { |c| set.call(ESCAPE, c, ParserAction::ESC_DISPATCH, GROUND) }
        set.call(ESCAPE, 0x59, ParserAction::ESC_DISPATCH, GROUND) # 'Y'
        set.call(ESCAPE, 0x5A, ParserAction::ESC_DISPATCH, GROUND) # 'Z'
        set.call(ESCAPE, 0x5C, ParserAction::ESC_DISPATCH, GROUND) # '\'
        (0x60..0x7E).each { |c| set.call(ESCAPE, c, ParserAction::ESC_DISPATCH, GROUND) }

        # --- ESCAPE_INTERMEDIATE ---
        executables.each { |c| set.call(ESCAPE_INTERMEDIATE, c, ParserAction::EXECUTE, ESCAPE_INTERMEDIATE) }
        set.call(ESCAPE_INTERMEDIATE, 0x7F, ParserAction::IGNORE, ESCAPE_INTERMEDIATE)
        (0x20..0x2F).each { |c| set.call(ESCAPE_INTERMEDIATE, c, ParserAction::COLLECT, ESCAPE_INTERMEDIATE) }
        (0x30..0x7E).each { |c| set.call(ESCAPE_INTERMEDIATE, c, ParserAction::ESC_DISPATCH, GROUND) }

        # --- CSI_ENTRY ---
        executables.each { |c| set.call(CSI_ENTRY, c, ParserAction::EXECUTE, CSI_ENTRY) }
        set.call(CSI_ENTRY, 0x7F, ParserAction::IGNORE, CSI_ENTRY)
        (0x40..0x7E).each { |c| set.call(CSI_ENTRY, c, ParserAction::CSI_DISPATCH, GROUND) }
        (0x30..0x3B).each { |c| set.call(CSI_ENTRY, c, ParserAction::PARAM, CSI_PARAM) }
        (0x3C..0x3F).each { |c| set.call(CSI_ENTRY, c, ParserAction::COLLECT, CSI_PARAM) }
        (0x20..0x2F).each { |c| set.call(CSI_ENTRY, c, ParserAction::COLLECT, CSI_INTERMEDIATE) }

        # --- CSI_PARAM ---
        executables.each { |c| set.call(CSI_PARAM, c, ParserAction::EXECUTE, CSI_PARAM) }
        set.call(CSI_PARAM, 0x7F, ParserAction::IGNORE, CSI_PARAM)
        (0x30..0x3B).each { |c| set.call(CSI_PARAM, c, ParserAction::PARAM, CSI_PARAM) }
        (0x40..0x7E).each { |c| set.call(CSI_PARAM, c, ParserAction::CSI_DISPATCH, GROUND) }
        (0x3C..0x3F).each { |c| set.call(CSI_PARAM, c, ParserAction::IGNORE, CSI_IGNORE) }
        (0x20..0x2F).each { |c| set.call(CSI_PARAM, c, ParserAction::COLLECT, CSI_INTERMEDIATE) }

        # --- CSI_INTERMEDIATE ---
        executables.each { |c| set.call(CSI_INTERMEDIATE, c, ParserAction::EXECUTE, CSI_INTERMEDIATE) }
        set.call(CSI_INTERMEDIATE, 0x7F, ParserAction::IGNORE, CSI_INTERMEDIATE)
        (0x20..0x2F).each { |c| set.call(CSI_INTERMEDIATE, c, ParserAction::COLLECT, CSI_INTERMEDIATE) }
        (0x30..0x3F).each { |c| set.call(CSI_INTERMEDIATE, c, ParserAction::IGNORE, CSI_IGNORE) }
        (0x40..0x7E).each { |c| set.call(CSI_INTERMEDIATE, c, ParserAction::CSI_DISPATCH, GROUND) }

        # --- CSI_IGNORE ---
        executables.each { |c| set.call(CSI_IGNORE, c, ParserAction::EXECUTE, CSI_IGNORE) }
        (0x20..0x3F).each { |c| set.call(CSI_IGNORE, c, ParserAction::IGNORE, CSI_IGNORE) }
        set.call(CSI_IGNORE, 0x7F, ParserAction::IGNORE, CSI_IGNORE)
        (0x40..0x7E).each { |c| set.call(CSI_IGNORE, c, ParserAction::IGNORE, GROUND) }

        # --- OSC_STRING ---
        executables.each { |c| set.call(OSC_STRING, c, ParserAction::IGNORE, OSC_STRING) }
        (0x20..0x7E).each { |c| set.call(OSC_STRING, c, ParserAction::OSC_PUT, OSC_STRING) }
        set.call(OSC_STRING, 0x7F, ParserAction::OSC_PUT, OSC_STRING)
        (0x1C..0x1F).each { |c| set.call(OSC_STRING, c, ParserAction::IGNORE, OSC_STRING) }
        set.call(OSC_STRING, 0x07, ParserAction::OSC_END, GROUND) # BEL terminates OSC
        set.call(OSC_STRING, NON_ASCII_PRINTABLE, ParserAction::OSC_PUT, OSC_STRING)

        # --- DCS_ENTRY ---
        executables.each { |c| set.call(DCS_ENTRY, c, ParserAction::IGNORE, DCS_ENTRY) }
        set.call(DCS_ENTRY, 0x7F, ParserAction::IGNORE, DCS_ENTRY)
        (0x1C..0x1F).each { |c| set.call(DCS_ENTRY, c, ParserAction::IGNORE, DCS_ENTRY) }
        (0x20..0x2F).each { |c| set.call(DCS_ENTRY, c, ParserAction::COLLECT, DCS_INTERMEDIATE) }
        (0x30..0x3B).each { |c| set.call(DCS_ENTRY, c, ParserAction::PARAM, DCS_PARAM) }
        (0x3C..0x3F).each { |c| set.call(DCS_ENTRY, c, ParserAction::COLLECT, DCS_PARAM) }
        (0x40..0x7E).each { |c| set.call(DCS_ENTRY, c, ParserAction::DCS_HOOK, DCS_PASSTHROUGH) }

        # --- DCS_PARAM ---
        executables.each { |c| set.call(DCS_PARAM, c, ParserAction::IGNORE, DCS_PARAM) }
        set.call(DCS_PARAM, 0x7F, ParserAction::IGNORE, DCS_PARAM)
        (0x1C..0x1F).each { |c| set.call(DCS_PARAM, c, ParserAction::IGNORE, DCS_PARAM) }
        (0x30..0x3B).each { |c| set.call(DCS_PARAM, c, ParserAction::PARAM, DCS_PARAM) }
        (0x3C..0x3F).each { |c| set.call(DCS_PARAM, c, ParserAction::IGNORE, DCS_IGNORE) }
        (0x20..0x2F).each { |c| set.call(DCS_PARAM, c, ParserAction::COLLECT, DCS_INTERMEDIATE) }
        (0x40..0x7E).each { |c| set.call(DCS_PARAM, c, ParserAction::DCS_HOOK, DCS_PASSTHROUGH) }

        # --- DCS_INTERMEDIATE ---
        executables.each { |c| set.call(DCS_INTERMEDIATE, c, ParserAction::IGNORE, DCS_INTERMEDIATE) }
        set.call(DCS_INTERMEDIATE, 0x7F, ParserAction::IGNORE, DCS_INTERMEDIATE)
        (0x1C..0x1F).each { |c| set.call(DCS_INTERMEDIATE, c, ParserAction::IGNORE, DCS_INTERMEDIATE) }
        (0x20..0x2F).each { |c| set.call(DCS_INTERMEDIATE, c, ParserAction::COLLECT, DCS_INTERMEDIATE) }
        (0x30..0x3F).each { |c| set.call(DCS_INTERMEDIATE, c, ParserAction::IGNORE, DCS_IGNORE) }
        (0x40..0x7E).each { |c| set.call(DCS_INTERMEDIATE, c, ParserAction::DCS_HOOK, DCS_PASSTHROUGH) }

        # --- DCS_PASSTHROUGH ---
        executables.each { |c| set.call(DCS_PASSTHROUGH, c, ParserAction::DCS_PUT, DCS_PASSTHROUGH) }
        (0x20..0x7E).each { |c| set.call(DCS_PASSTHROUGH, c, ParserAction::DCS_PUT, DCS_PASSTHROUGH) }
        set.call(DCS_PASSTHROUGH, 0x7F, ParserAction::IGNORE, DCS_PASSTHROUGH)
        set.call(DCS_PASSTHROUGH, NON_ASCII_PRINTABLE, ParserAction::DCS_PUT, DCS_PASSTHROUGH)

        # --- DCS_IGNORE ---
        executables.each { |c| set.call(DCS_IGNORE, c, ParserAction::IGNORE, DCS_IGNORE) }
        (0x20..0x7F).each { |c| set.call(DCS_IGNORE, c, ParserAction::IGNORE, DCS_IGNORE) }
        set.call(DCS_IGNORE, NON_ASCII_PRINTABLE, ParserAction::IGNORE, DCS_IGNORE)

        # --- SOS_PM_STRING ---
        executables.each { |c| set.call(SOS_PM_STRING, c, ParserAction::IGNORE, SOS_PM_STRING) }
        (0x20..0x7E).each { |c| set.call(SOS_PM_STRING, c, ParserAction::SOS_PM_PUT, SOS_PM_STRING) }
        set.call(SOS_PM_STRING, 0x7F, ParserAction::IGNORE, SOS_PM_STRING)
        set.call(SOS_PM_STRING, NON_ASCII_PRINTABLE, ParserAction::SOS_PM_PUT, SOS_PM_STRING)

        # --- APC_STRING ---
        executables.each { |c| set.call(APC_STRING, c, ParserAction::IGNORE, APC_STRING) }
        (0x20..0x7E).each { |c| set.call(APC_STRING, c, ParserAction::APC_PUT, APC_STRING) }
        set.call(APC_STRING, 0x7F, ParserAction::IGNORE, APC_STRING)
        set.call(APC_STRING, NON_ASCII_PRINTABLE, ParserAction::APC_PUT, APC_STRING)

        table
      end
    end
  end
end
