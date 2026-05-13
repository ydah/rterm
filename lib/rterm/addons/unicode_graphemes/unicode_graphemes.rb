# frozen_string_literal: true

require_relative "../base"
require_relative "../../common/unicode/unicode_handler"

module RTerm
  module Addon
    class UnicodeGraphemes < Base
      VERSION = "graphemes"

      class Provider
        def initialize(version: VERSION, base_version: nil)
          @version = version.to_s
          @base_version = base_version.to_s
          @handler = Common::UnicodeHandler.new
          @handler.active_version = @base_version if @handler.versions.include?(@base_version)
        end

        attr_reader :version, :base_version

        def char_width(codepoint)
          @handler.char_width(codepoint)
        end

        def wcwidth(codepoint)
          char_width(codepoint)
        end

        def grapheme_width(cluster)
          @handler.char_width(cluster.to_s)
        end

        def grapheme_clusters(text)
          @handler.grapheme_clusters(text)
        end

        def string_width(text)
          grapheme_clusters(text).sum { |cluster| grapheme_width(cluster) }
        end
      end

      def initialize(version: VERSION, base_version: nil)
        @version = version.to_s
        @base_version = base_version&.to_s
        @previous_version = nil
        @provider = nil
        @active = false
      end

      attr_reader :version, :base_version, :previous_version, :provider

      def activate(terminal)
        super
        @previous_version = terminal.unicode.active_version
        provider_base_version = @base_version || @previous_version
        @provider = Provider.new(version: @version, base_version: provider_base_version)
        terminal.unicode.register(@version, @provider)
        terminal.unicode.active_version = @version
        @active = true
      end

      def active?
        @active && @terminal&.unicode&.active_version == @version
      end

      def grapheme_clusters(text)
        active_provider.grapheme_clusters(text)
      end

      def string_width(text)
        active_provider.string_width(text)
      end

      def dispose
        restore_previous_version
        @active = false
        super
      end

      alias active active?
      alias graphemeClusters grapheme_clusters
      alias stringWidth string_width

      private

      def active_provider
        @provider || Provider.new(version: @version, base_version: @base_version)
      end

      def restore_previous_version
        return unless @terminal && @previous_version
        return unless @terminal.unicode.versions.include?(@previous_version)

        @terminal.unicode.active_version = @previous_version
      end
    end
  end
end
