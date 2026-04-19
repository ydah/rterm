# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/rterm"

puts "=== RTerm Large Scrollback Benchmark ==="
Benchmark.bm(28) do |x|
  x.report("retain 50k lines") do
    term = RTerm::Terminal.new(cols: 100, rows: 30, scrollback: 50_000)
    50_000.times { |index| term.writeln("scrollback line #{index}") }
    term.scroll_to_top
    term.scroll_to_bottom
  end
end
