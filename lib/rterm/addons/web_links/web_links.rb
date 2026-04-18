# frozen_string_literal: true

require_relative "../base"
require_relative "logical_line_builder"
require_relative "link_range"

module RTerm
  module Addon
    class WebLinks < Base
      URL_REGEX = %r{(?<![\w@])https?://[^\s<>\[\]{}|\\^`"']+}i
      TRAILING_PUNCTUATION = ".,;:!?"

      def initialize
        @providers = []
        @link_handlers = []
      end

      # Registers an additional link provider.
      # Providers receive |text, row| and return link hashes.
      # @return [Common::Disposable]
      def register_link_provider(provider = nil, &block)
        provider ||= block
        raise ArgumentError, "link provider is required" unless provider

        @providers << provider
        Common::Disposable.new { @providers.delete(provider) }
      end

      # Registers a callback invoked by #open_link.
      # @return [Common::Disposable]
      def on_link(&block)
        raise ArgumentError, "link handler block is required" unless block

        @link_handlers << block
        Common::Disposable.new { @link_handlers.delete(block) }
      end

      # Find all URLs in the buffer
      # @param row [Integer, nil] optional visible row filter
      # @return [Array<Hash>] array of {url:, row:, col:, length:}
      def find_links(row: nil)
        lines = logical_lines(row: row)
        links = detected_links(lines) + provider_links(lines)
        links.sort_by { |link| [link[:row], link[:col], link[:url].to_s] }
      end

      # xterm.js-style provider entry point. Returns and optionally yields links.
      # @param row [Integer] visible row
      # @yield [Array<Hash>]
      # @return [Array<Hash>]
      def provide_links(row, &callback)
        links = find_links(row: row)
        callback&.call(links)
        links
      end

      # Finds a link at the given visible cell position.
      # @param row [Integer]
      # @param col [Integer]
      # @return [Hash, nil]
      def link_at(row, col)
        find_links(row: row).find do |link|
          link[:ranges].any? do |range|
            range[:row] == row && col >= range[:col] && col < range[:col] + range[:length]
          end
        end
      end

      # Invokes registered link handlers for a link hash or index from #find_links.
      # @param link_or_index [Hash, Integer]
      # @return [Boolean] whether a link was opened
      def open_link(link_or_index)
        link = link_or_index.is_a?(Integer) ? find_links[link_or_index] : link_or_index
        return false unless link

        link[:activate]&.call(link)
        @link_handlers.each { |handler| handler.call(link) }
        true
      end

      private

      def detected_links(lines)
        lines.flat_map do |line|
          line[:text].scan(URL_REGEX).filter_map do
            match = Regexp.last_match
            raw_url = match[0]
            url = trim_url(raw_url)
            next if url.empty?

            start = match.pre_match.length
            length = url.length
            build_link(url: url, line: line, start: start, length: length)
          end
        end
      end

      def provider_links(lines)
        @providers.flat_map do |provider|
          lines.flat_map do |line|
            normalize_provider_links(call_provider(provider, line), line)
          end
        end
      end

      def call_provider(provider, line)
        if provider.respond_to?(:provide_links)
          provider.provide_links(line[:text], line[:start_row])
        else
          provider.call(line[:text], line[:start_row])
        end
      end

      def normalize_provider_links(links, line)
        Array(links).filter_map do |link|
          url = (link[:url] || link["url"]).to_s
          next if url.empty?

          start = link[:start] || link["start"] || link[:index] || link["index"]
          length = link[:length] || link["length"] || url.length
          if start
            build_link(url: url, line: line, start: start.to_i, length: length.to_i, activate: link[:activate])
          else
            normalize_physical_link(link, url, length)
          end
        end
      end

      def normalize_physical_link(link, url, length)
        row = link[:row] || link["row"]
        col = link[:col] || link["col"]
        return nil unless row && col

        length = length.to_i
        {
          url: url,
          row: row.to_i,
          col: col.to_i,
          length: length,
          text: link[:text] || link["text"] || url,
          ranges: [{ row: row.to_i, col: col.to_i, length: length }],
          activate: link[:activate]
        }
      end

      def build_link(url:, line:, start:, length:, activate: nil)
        position = LinkRange.position_for(line[:segments], start)
        ranges = LinkRange.ranges_for(line[:segments], start, length)
        return nil unless position && ranges.any?

        {
          url: url,
          row: position[:row],
          col: position[:col],
          length: length,
          text: url,
          ranges: ranges,
          activate: activate
        }
      end

      def logical_lines(row: nil)
        buffer = @terminal.internal.buffer_set.active
        LogicalLineBuilder.new(buffer).call(row: row)
      end

      def trim_url(url)
        url = url.dup
        loop do
          last = url[-1]
          break unless last

          if TRAILING_PUNCTUATION.include?(last)
            url.chop!
          elsif last == ")" && url.count(")") > url.count("(")
            url.chop!
          else
            break
          end
        end
        url
      end
    end
  end
end
