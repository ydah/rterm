# RTerm

RTerm is a headless terminal emulator library for Ruby. It owns terminal state,
ANSI/VT parsing, scrollback, PTY integration, and BrowserBridge transport
helpers; rendering stays in the host application.

## Overview

- ANSI/VT escape sequence parsing and xterm-style buffer management
- Unicode-aware cell handling, wrapped-line reflow, scrollback, selection, and mouse reporting
- OSC/DCS support including OSC 8 hyperlinks, OSC 52 clipboard policy hooks, Sixel, and iTerm2 image metadata
- PTY integration for interactive shell processes, including cwd/env, stdin close, pause/resume, process groups, and exit lifecycle
- Browser bridge protocol for WebSocket-based terminal apps with session resume, attach policies, rate limits, heartbeat timeouts, origin checks, and binary negotiation
- Addons: Search, Serialize, Fit, WebLinks

## Requirements

- Ruby 3.2 or later

## Installation

```ruby
# Gemfile
gem "rterm"

# BrowserBridge Rack/WebSocket deployment also needs:
gem "faye-websocket"
```

```bash
gem install rterm
```

## Usage

```ruby
require "rterm"

term = RTerm::Terminal.new(cols: 80, rows: 24, scrollback: 1_000)
term.write("Hello \e[1;31mWorld\e[0m!\r\n")

line = term.buffer.active.get_line(0)
puts line.to_string # => "Hello World!"
```

## Addons

Search:

```ruby
search = RTerm::Addon::Search.new
term.load_addon(search)

term.write("error: failed\r\nerror: retrying")
state = search.update("error", decorations: { background: "#ffff00" })
puts state[:matches].length # => 2

matches = search.find_all("error: (?<reason>\\w+)", regex: true)
puts matches.first[:captures].first[:name] # => "reason"
```

Serialize:

```ruby
serializer = RTerm::Addon::Serialize.new
term.load_addon(serializer)

ansi = serializer.serialize(scrollback: 100)
snapshot = serializer.snapshot(scrollback: 100)

restored = RTerm::Terminal.new(cols: 80, rows: 24)
restored_serializer = RTerm::Addon::Serialize.new
restored.load_addon(restored_serializer)
restored_serializer.restore(snapshot)
```

WebLinks:

```ruby
links = RTerm::Addon::WebLinks.new
term.load_addon(links)

term.write("open https://example.com")
link = links.find_links.first
links.on_link { |item| puts "open #{item[:url]}" }
links.open_link(link)
```

## Terminal APIs

Selection and mouse helpers:

```ruby
term.write("open https://example.com\r\n")
term.select_url(8, 0)
puts term.selection # => "https://example.com"

term.write("\e[?1006h\e[?1000h")
term.mouse_event(button: :left, col: 4, row: 2)
```

Renderer-facing policy helpers:

```ruby
cell = term.buffer.active.get_line(0).get_cell(0)
colors = term.cell_colors(cell)
cursor = term.cursor_info(active: false)
```

PTY:

```ruby
pty = RTerm::Pty.new(
  command: ENV["SHELL"] || "/bin/sh",
  env: { "TERM" => "xterm-256color" },
  cwd: Dir.pwd,
  process_group: true
)

pty.on_data { |data| term.write(data) }
pty.write("printf 'hello\\n'\r")
pty.close
```

BrowserBridge:

```ruby
manager = RTerm::BrowserBridge::SessionManager.new(
  max_sessions: 10,
  idle_timeout: 600,
  attach_policy: :single
)

message = RTerm::BrowserBridge::ProtocolHandler.decode(
  '{"type":"create_session","payload":{"cols":80,"rows":24}}'
)
response = manager.process_message(message)
```

Production BrowserBridge setup:

```ruby
RTerm::BrowserBridge::WebSocketServer.configure_secure_defaults do |config|
  config.allowed_origins = ["https://your-app.example"]
  config.authenticator = lambda do |message|
    payload = message[:payload] || message["payload"] || {}
    token = payload[:token] || payload["token"]

    token == ENV.fetch("RTERM_BRIDGE_TOKEN")
  end
  config.terminal_options = config.terminal_options.merge(scrollback: 5_000)
end
```

More examples:

- `examples/basic_usage.rb`
- `examples/addons.rb`
- `examples/websocket_server.rb`
- `examples/browser_bridge_production.rb`

## Security Notes

- Disable clipboard handling for untrusted remote output with `clipboard_enabled: false`.
- Set `allowed_origins` for BrowserBridge deployments.
- Keep message size limits, rate limits, and heartbeat timeouts enabled in production.
- PTY commands run with the host process permissions; do not connect untrusted browser input directly to a privileged shell.
- Validate URI schemes in the host app before activating OSC 8 hyperlinks.

## Platform Status

- Unix PTY: supported through the PTY backend.
- Windows ConPTY: planned, but not implemented yet.
- Rendering: intentionally out of scope; rterm is a headless core.

## Documentation

- Security policy: `docs/security_policy.md`
- Renderer and font measurement scope: `docs/renderer_scope.md`
- Release checklist: `docs/release_checklist.md`

## Development

```bash
git clone https://github.com/ydah/rterm.git
cd rterm
bundle install
bundle exec rspec
bundle exec rake package:verify_contents
```

Benchmarks live under `spec/benchmarks/` and can be run directly with Ruby, for example:

```bash
ruby spec/benchmarks/parser_benchmark.rb
ruby spec/benchmarks/search_benchmark.rb
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
