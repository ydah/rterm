# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/rterm"

term = RTerm::Terminal.new(cols: 120, rows: 40, scrollback: 20_000)

puts "=== RTerm Buffer Benchmark ==="
Benchmark.bm(28) do |x|
  x.report("write 10k lines") do
    10_000.times { |index| term.writeln("line #{index} #{'x' * 80}") }
  end

  x.report("read visible rows") do
    2_000.times { term.buffer.active.get_line(0)&.to_string }
  end

  x.report("select scrollback") do
    100.times do
      term.select_all
      term.selection
    end
  end
end
