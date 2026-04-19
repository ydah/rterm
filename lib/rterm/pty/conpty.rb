# frozen_string_literal: true

module RTerm
  # Boundary for a future Windows ConPTY-backed PTY adapter.
  class ConPTY
    class UnsupportedPlatformError < StandardError; end

    # @return [Boolean]
    def self.supported?
      Gem.win_platform?
    end

    def initialize(*)
      raise UnsupportedPlatformError, "RTerm::ConPTY is only available on Windows" unless self.class.supported?

      raise NotImplementedError, "RTerm::ConPTY adapter boundary is present, but the Windows backend is not implemented"
    end
  end
end
