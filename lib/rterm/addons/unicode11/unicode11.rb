# frozen_string_literal: true

require_relative "../base"

module RTerm
  module Addon
    class Unicode11 < Base
      VERSION = "11"

      def initialize
        @previous_version = nil
        @active = false
      end

      attr_reader :previous_version

      def activate(terminal)
        super
        @previous_version = terminal.unicode.active_version
        terminal.unicode.active_version = VERSION
        @active = true
      end

      def version
        VERSION
      end

      def active?
        @active && @terminal&.unicode&.active_version == VERSION
      end

      def dispose
        restore_previous_version
        @active = false
        super
      end

      alias active active?

      private

      def restore_previous_version
        return unless @terminal && @previous_version
        return unless @terminal.unicode.versions.include?(@previous_version)

        @terminal.unicode.active_version = @previous_version
      end
    end
  end
end
