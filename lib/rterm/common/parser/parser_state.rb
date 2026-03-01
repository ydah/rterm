# frozen_string_literal: true

module RTerm
  module Common
    # Parser state machine states, mirroring xterm.js ParserState.
    module ParserState
      GROUND              = 0
      ESCAPE              = 1
      ESCAPE_INTERMEDIATE = 2
      CSI_ENTRY           = 3
      CSI_PARAM           = 4
      CSI_INTERMEDIATE    = 5
      CSI_IGNORE          = 6
      SOS_PM_STRING       = 7
      OSC_STRING          = 8
      DCS_ENTRY           = 9
      DCS_PARAM           = 10
      DCS_IGNORE          = 11
      DCS_INTERMEDIATE    = 12
      DCS_PASSTHROUGH     = 13
      APC_STRING          = 14
      STATE_LENGTH        = 15
    end

    # Parser action types.
    module ParserAction
      IGNORE       = 0
      ERROR        = 1
      PRINT        = 2
      EXECUTE      = 3
      OSC_START    = 4
      OSC_PUT      = 5
      OSC_END      = 6
      CSI_DISPATCH = 7
      PARAM        = 8
      COLLECT      = 9
      ESC_DISPATCH = 10
      CLEAR        = 11
      DCS_HOOK     = 12
      DCS_PUT      = 13
      DCS_UNHOOK   = 14
      APC_START    = 15
      APC_PUT      = 16
      APC_END      = 17
    end
  end
end
