# frozen_string_literal: true

require_relative "unicode_handler"

module RTerm
  module Common
    # Unicode 15 width provider.
    class UnicodeV15 < UnicodeHandler
      def initialize
        super
        self.active_version = "15"
      end
    end
  end
end
