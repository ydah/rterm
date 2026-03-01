# frozen_string_literal: true

require_relative "../../lib/rterm"
require "benchmark"

plain_text = "Hello World! This is a test line with normal text.\r\n" * 1000
escape_heavy = "\e[1;31mRed\e[0m \e[32mGreen\e[0m \e[34mBlue\e[0m \e[38;2;255;128;0mOrange\e[0m\r\n" * 1000
mixed_data = "$ ls -la\r\n\e[01;34mdir\e[0m  \e[01;32mscript.sh\e[0m  file.txt\r\n" * 1000
cursor_heavy = "\e[H\e[2J" + (1..24).map { |r| "\e[#{r};1H#{"x" * 80}" }.join * 50

puts "=== RTerm Parser Benchmark ==="
puts "Ruby #{RUBY_VERSION}"
puts "Plain text size: #{plain_text.bytesize} bytes"
puts "Escape-heavy size: #{escape_heavy.bytesize} bytes"
puts

Benchmark.bm(25) do |x|
  x.report("plain text") { RTerm::Terminal.new(cols: 80, rows: 24).write(plain_text) }
  x.report("escape-heavy") { RTerm::Terminal.new(cols: 80, rows: 24).write(escape_heavy) }
  x.report("mixed") { RTerm::Terminal.new(cols: 80, rows: 24).write(mixed_data) }
  x.report("cursor-heavy") { RTerm::Terminal.new(cols: 80, rows: 24).write(cursor_heavy) }
end

puts
puts "=== Buffer Benchmark ==="
Benchmark.bm(25) do |x|
  x.report("scroll 1000 lines") do
    term = RTerm::Terminal.new(cols: 80, rows: 24, scrollback: 10_000)
    1000.times { |i| term.writeln("Line #{i}") }
  end

  x.report("resize 100 times") do
    term = RTerm::Terminal.new(cols: 80, rows: 24)
    100.times do |i|
      term.resize(80 + (i % 40), 24 + (i % 16))
    end
  end
end
