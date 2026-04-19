# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/rterm"

payload = Array.new(2_000) { |index| "word#{index} #{'x' * 30}" }.join(" ")

puts "=== RTerm Resize/Reflow Benchmark ==="
Benchmark.bm(28) do |x|
  x.report("resize active buffer") do
    term = RTerm::Terminal.new(cols: 80, rows: 24, scrollback: 5_000)
    term.write(payload)
    200.times do |index|
      term.resize(60 + (index % 80), 20 + (index % 20))
    end
  end
end
