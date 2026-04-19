# frozen_string_literal: true

require_relative "../base"
require_relative "logical_line_builder"
require_relative "link_range"

module RTerm
  module Addon
    class WebLinks < Base
      URL_REGEX = %r{(?<![\w@])https?://[^\s<>\[\]{}|\\^`"']+}i
      TRAILING_PUNCTUATION = ".,;:!?"
      ASYNC_PENDING = Object.new.freeze

      class LinkRequest
        def initialize(row)
          @row = row
          @cancelled = false
        end

        attr_reader :row

        def cancel
          @cancelled = true
        end

        def cancelled?
          @cancelled
        end
      end

      def initialize
        @providers = []
        @link_handlers = []
        @link_requests = []
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

      # Asynchronously provides links for a visible row.
      # Providers with arity 4 receive |text, row, request, callback| and may
      # invoke callback later. The returned disposable cancels pending callbacks.
      # @param row [Integer]
      # @yield [Array<Hash>]
      # @return [Common::Disposable]
      def provide_links_async(row, &callback)
        raise ArgumentError, "callback block is required" unless callback

        request = LinkRequest.new(row.to_i)
        @link_requests << request
        lines = logical_lines(row: row)
        results = detected_links(lines)
        tasks = provider_tasks(lines)
        return complete_link_request(request, results, callback) if tasks.empty?

        pending = tasks.length
        tasks.each do |provider, line|
          call_provider_async(provider, line, request) do |links|
            next if request.cancelled?

            results.concat(normalize_provider_links(links, line))
            pending -= 1
            complete_link_request(request, results, callback) if pending.zero?
          end
        end

        Common::Disposable.new { cancel_link_request(request) }
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
        link = resolve_link(link_or_index)
        return false unless link

        link[:activate]&.call(link)
        emit_link_lifecycle(:activate, link)
        @link_handlers.each { |handler| handler.call(link) }
        true
      end

      alias activate_link open_link

      # Invokes hover lifecycle handlers for a link hash, index, or cell position.
      # @return [Boolean]
      def hover_link(link_or_index = nil, row: nil, col: nil)
        link = resolve_link(link_or_index, row: row, col: col)
        return false unless link

        link[:hover]&.call(link)
        emit_link_lifecycle(:hover, link)
        true
      end

      # Invokes leave lifecycle handlers for a link hash, index, or cell position.
      # @return [Boolean]
      def leave_link(link_or_index = nil, row: nil, col: nil)
        link = resolve_link(link_or_index, row: row, col: col)
        return false unless link

        link[:leave]&.call(link)
        emit_link_lifecycle(:leave, link)
        true
      end

      def dispose
        @link_requests.each(&:cancel)
        @link_requests.clear
        super
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
        provider_tasks(lines).flat_map do |provider, line|
          normalize_provider_links(call_provider(provider, line), line)
        end
      end

      def provider_tasks(lines)
        @providers.product(lines)
      end

      def call_provider(provider, line)
        if provider.respond_to?(:provide_links)
          provider.provide_links(line[:text], line[:start_row])
        else
          provider.call(line[:text], line[:start_row])
        end
      end

      def call_provider_async(provider, line, request, &callback)
        result = if provider.respond_to?(:provide_links_async)
                   provider.provide_links_async(line[:text], line[:start_row], request, &callback) || ASYNC_PENDING
                 elsif provider.respond_to?(:provide_links)
                   call_provider_method(provider.method(:provide_links), line, request)
                 else
                   call_provider_block(provider, line, request, callback)
                 end
        callback.call(result) unless async_pending?(result)
      rescue StandardError
        callback.call([])
      end

      def call_provider_block(provider, line, request, callback)
        arity = provider.arity
        if arity >= 4
          provider.call(line[:text], line[:start_row], request, callback)
          ASYNC_PENDING
        elsif arity == 3
          provider.call(line[:text], line[:start_row], request)
        else
          provider.call(line[:text], line[:start_row])
        end
      end

      def call_provider_method(method, line, request)
        if method.arity >= 3 || method.arity.negative?
          method.call(line[:text], line[:start_row], request)
        else
          method.call(line[:text], line[:start_row])
        end
      end

      def async_pending?(result)
        result.equal?(ASYNC_PENDING) || result.respond_to?(:dispose)
      end

      def normalize_provider_links(links, line)
        Array(links).filter_map do |link|
          url = (link[:url] || link["url"]).to_s
          next if url.empty?

          start = link[:start] || link["start"] || link[:index] || link["index"]
          length = link[:length] || link["length"] || url.length
          if start
            build_link(
              url: url,
              line: line,
              start: start.to_i,
              length: length.to_i,
              activate: link_callback(link, :activate),
              hover: link_callback(link, :hover),
              leave: link_callback(link, :leave)
            )
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
          activate: link_callback(link, :activate),
          hover: link_callback(link, :hover),
          leave: link_callback(link, :leave)
        }
      end

      def build_link(url:, line:, start:, length:, activate: nil, hover: nil, leave: nil)
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
          activate: activate,
          hover: hover,
          leave: leave
        }
      end

      def link_callback(link, name)
        link[name] || link[name.to_s]
      end

      def resolve_link(link_or_index, row: nil, col: nil)
        return link_or_index if link_or_index.is_a?(Hash)
        return find_links[link_or_index] if link_or_index.is_a?(Integer)
        return link_at(row.to_i, col.to_i) if !row.nil? && !col.nil?

        nil
      end

      def emit_link_lifecycle(action, link)
        @terminal.internal.emit(:"web_link_#{action}", link)
        @terminal.internal.emit(:web_link, { action: action, link: link })
      end

      def complete_link_request(request, results, callback)
        return Common::Disposable.new { cancel_link_request(request) } if request.cancelled?

        @link_requests.delete(request)
        callback.call(results.sort_by { |link| [link[:row], link[:col], link[:url].to_s] })
        Common::Disposable.new { cancel_link_request(request) }
      end

      def cancel_link_request(request)
        request.cancel
        @link_requests.delete(request)
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
