# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/rterm"

shell = ENV["SHELL"] || "/bin/sh"
command = "i=0; while [ $i -lt 2000 ]; do printf 'line %s\\n' \"$i\"; i=$((i+1)); done"

puts "=== RTerm PTY Throughput Benchmark ==="
Benchmark.bm(28) do |x|
  x.report("pty read 2k lines") do
    term = RTerm::Terminal.new(cols: 100, rows: 30)
    pty = RTerm::Pty.new(command: shell, args: ["-lc", command], env: { "TERM" => "xterm-256color" })
    pty.on_data { |data| term.write(data) }
    pty.wait_for_exit(5.0)
    pty.close
  end
end
