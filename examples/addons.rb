# frozen_string_literal: true

require_relative "../lib/rterm"

terminal = RTerm::Terminal.new(cols: 80, rows: 24, scrollback: 1_000)
search = RTerm::Addon::Search.new
serializer = RTerm::Addon::Serialize.new
links = RTerm::Addon::WebLinks.new

terminal.load_addon(search)
terminal.load_addon(serializer)
terminal.load_addon(links)

terminal.write("Read https://example.com/docs and run printf\r\n")

search.update("example", decorations: { background: "#ffff00" })
puts "Search matches: #{search.state[:matches].length}"

links.on_link { |link| puts "Open link: #{link[:url]}" }
links.open_link(links.find_links.first)

snapshot = serializer.snapshot(scrollback: 10)
puts "Snapshot buffers: #{snapshot.fetch('buffers').keys.join(', ')}"
