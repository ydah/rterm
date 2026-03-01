# frozen_string_literal: true

module RTerm
  module Addon
    class Base
      def activate(terminal)
        @terminal = terminal
      end

      def dispose
      end
    end
  end
end
