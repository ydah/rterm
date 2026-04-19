# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/rterm"

term = RTerm::Terminal.new(cols: 120, rows: 40, scrollback: 5_000)
serializer = RTerm::Addon::Serialize.new
term.load_addon(serializer)
2_000.times { |index| term.writeln("\e[3#{index % 8}mline #{index}\e[0m #{'x' * 80}") }

puts "=== RTerm Serialize Benchmark ==="
Benchmark.bm(28) do |x|
  x.report("ansi serialize") { 100.times { serializer.serialize(scrollback: 1_000) } }
  x.report("structured snapshot") { 100.times { serializer.snapshot(scrollback: 1_000) } }
  x.report("html serialize") { 100.times { serializer.serialize_as_html(scrollback: 1_000) } }
end
