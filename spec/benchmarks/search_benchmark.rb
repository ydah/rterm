# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/rterm"

term = RTerm::Terminal.new(cols: 120, rows: 40, scrollback: 10_000)
search = RTerm::Addon::Search.new
term.load_addon(search)
5_000.times { |index| term.writeln("path=/tmp/rterm/#{index} status=#{index % 7 == 0 ? 'error' : 'ok'}") }

puts "=== RTerm Search Benchmark ==="
Benchmark.bm(28) do |x|
  x.report("plain search") { 100.times { search.find_all("status=error", scrollback: :all) } }
  x.report("regex captures") { 100.times { search.find_all("status=(error|ok)", regex: true, scrollback: :all) } }
  x.report("decorations") do
    100.times { search.find_all("status=error", scrollback: :all, decorations: { background: "#ffff00" }) }
  end
end
