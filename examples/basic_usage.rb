# frozen_string_literal: true

require_relative "../lib/rterm"

# Basic headless terminal usage
term = RTerm::Terminal.new(cols: 80, rows: 24)

# Write text with ANSI colors
term.write("Hello \e[1;31mWorld\e[0m!\r\n")
term.write("\e[38;2;0;255;128mTrueColor text\e[0m\r\n")

# Read buffer content
line = term.buffer.active.get_line(0)
puts line.to_string # => "Hello World!"

# Check cell attributes
cell = line.get_cell(6) # 'W' in World
puts "Bold: #{cell.bold?}"         # => true
puts "Color mode: #{cell.fg_color_mode}" # => :p16

# Listen to events
term.on(:bell) { puts "Bell!" }
term.on(:title_change) { |title| puts "Title: #{title}" }

# Set title
term.write("\e]0;My Terminal\x07")

# Use addons
search = RTerm::Addon::Search.new
term.load_addon(search)

term.writeln("Find me in the buffer")
matches = search.find_all("Find")
puts "Found #{matches.length} match(es)"

# Serialize
serializer = RTerm::Addon::Serialize.new
term.load_addon(serializer)
puts serializer.serialize_as_html

# Cleanup
term.dispose
