# RTerm

RTerm is a headless terminal emulator library for Ruby.

## Overview

- ANSI/VT escape sequence parsing and terminal buffer management
- PTY integration for interactive shell processes
- Browser bridge protocol for WebSocket-based terminal apps
- Addons: Search, Serialize, Fit, WebLinks

## Requirements

- Ruby 3.2 or later

## Installation

```ruby
# Gemfile
gem "rterm"
```

```bash
gem install rterm
```

## Usage

```ruby
require "rterm"

term = RTerm::Terminal.new(cols: 80, rows: 24)
term.write("Hello \e[1;31mWorld\e[0m!\r\n")

line = term.buffer.active.get_line(0)
puts line.to_string # => "Hello World!"
```

More examples:

- `examples/basic_usage.rb`
- `examples/websocket_server.rb`

## Development

```bash
git clone https://github.com/ydah/rterm.git
cd rterm
bundle install
bundle exec rspec
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
