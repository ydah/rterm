# frozen_string_literal: true

require_relative "unicode_handler"

module RTerm
  module Common
    # Unicode 11 width provider.
    class UnicodeV11 < UnicodeHandler
      def initialize
        super
        self.active_version = "11"
      end
    end
  end
end
