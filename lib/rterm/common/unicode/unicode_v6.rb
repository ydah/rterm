# frozen_string_literal: true

require_relative "unicode_handler"

module RTerm
  module Common
    # Unicode 6 width provider.
    class UnicodeV6 < UnicodeHandler
      def initialize
        super
        self.active_version = "6"
      end
    end
  end
end
