# RTerm

RTerm is a headless terminal emulator library for Ruby. It owns terminal state,
ANSI/VT parsing, scrollback, PTY integration, and BrowserBridge transport
helpers; rendering stays in the host application.

## Overview

- ANSI/VT escape sequence parsing and terminal buffer management
- Unicode-aware cell handling, wrapped-line reflow, scrollback, selection, and mouse reporting
- OSC/DCS support including OSC 8 hyperlinks, OSC 52 clipboard policy hooks, Sixel, and iTerm2 image metadata
- PTY integration for interactive shell processes, including cwd/env, stdin close, pause/resume, process groups, and exit lifecycle
- Browser bridge protocol for WebSocket-based terminal apps with session resume, attach policies, rate limits, heartbeat timeouts, origin checks, and binary negotiation
- Addons: Attach, Search, Serialize, Fit, Clipboard, Progress, Image, Ligatures, Unicode11, UnicodeGraphemes, WebFonts, Canvas, WebGL, WebLinks

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

Clipboard:

```ruby
clipboard = RTerm::Addon::Clipboard.new
term.load_addon(clipboard)

clipboard.write_text("ready")
clipboard.paste
```

Progress:

```ruby
progress = RTerm::Addon::Progress.new
term.load_addon(progress)

progress.on_change { |state| puts "#{state[:name]} #{state[:value]}%" }
term.write("\e]9;4;1;50\a")
```

Attach:

```ruby
attach = RTerm::Addon::Attach.new(socket)
term.load_addon(attach)
```

Image metadata:

```ruby
images = RTerm::Addon::Image.new
term.load_addon(images)

images.on_image { |image| puts image[:protocol] }
images.register_decoder(:sixel) { |image| { bytes: image[:data].bytesize } }
images.on_render_request { |request| puts request[:protocol] }
term.write("\ePqABCDEF\e\\")
images.render_all(protocol: :sixel, target: :canvas)
```

Ligature ranges:

```ruby
ligatures = RTerm::Addon::Ligatures.new
term.load_addon(ligatures)
puts ligatures.ranges("a => b").first # => {:start=>2, :end=>4, :text=>"=>", :row=>nil}
```

Unicode width helpers:

```ruby
term.load_addon(RTerm::Addon::Unicode11.new)

graphemes = RTerm::Addon::UnicodeGraphemes.new
term.load_addon(graphemes)
puts graphemes.string_width("a©️b") # => 4
```

Web fonts:

```ruby
fonts = RTerm::Addon::WebFonts.new(false)
term.load_addon(fonts)

fonts.register_font(
  "JetBrains Mono",
  "url('/fonts/jetbrains.woff2') format('woff2')",
  weight: 400,
  display: "swap"
)

puts fonts.font_face_css
fonts.relayout
```

WebGL renderer state:

```ruby
renderer = RTerm::Addon::WebGL.new
term.load_addon(renderer)

renderer.on_context_loss { |event| warn event[:reason] }
renderer.attach_host(:canvas, viewport: { cellWidth: 9, cellHeight: 18 })
renderer.update_scrollbar(visible: true, width: 12)
term.refresh(0, term.rows - 1)
puts renderer.last_render # => {:start=>0, :end=>23, :rows=>[0, ...]}
renderer.clear_texture_atlas
```

Screen renderer tree:

```ruby
screen = RTerm::Addon::ScreenRenderer.new
term.load_addon(screen)
term.write("hello")

puts screen.text
puts screen.accessibility_tree[:children].first[:text]
```

Canvas renderer state:

```ruby
renderer = RTerm::Addon::Canvas.new
term.load_addon(renderer)

renderer.on_render_cache_clear { |event| puts event[:count] }
term.refresh(0, term.rows - 1)
puts renderer.last_render # => {:start=>0, :end=>23, :rows=>[0, ...]}
renderer.clear_render_cache
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

Resize and erase behavior:

```ruby
term = RTerm::Terminal.new(
  reflowCursorLine: true,
  scrollOnEraseInDisplay: true,
  ignoreBracketedPasteMode: true
)
```

Synchronized output mode:

```ruby
term.write("\e[?2026h")
term.write("batch")
puts term.modes[:synchronized_output_mode] # => true
term.write("\e[?2026l")
```

Input surface:

```ruby
term.open
term.on_textarea_input { |event| puts event[:data] }
term.on_accessibility { |event| puts event[:last_announcement] }
term.textarea.input("ls\r")
term.textarea.composition_start("k")
term.textarea.composition_update("ka")
term.textarea.composition_end("ka")
```

Decorations:

```ruby
marker = term.register_marker
decoration = term.register_decoration(
  marker,
  x: 2,
  width: 8,
  className: "highlight",
  backgroundColor: "#334155",
  overviewRulerOptions: { color: "#334155", position: "full" }
)

decoration.on_render { |element| puts element.dataset["row"] }
term.refresh(0, term.rows - 1)
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

ConPTY backend adapter:

```ruby
RTerm::ConPTY.configure_backend(lambda { |**options| MyConPTYBackend.new(**options) })
conpty = RTerm::ConPTY.new(command: "cmd.exe", cols: 80, rows: 24)
conpty.on_data { |data| term.write(data) }
```

## Platform Status

- Unix PTY: supported through the PTY backend.
- Windows ConPTY: adapter API is available; native process handling is supplied by the host backend.
- Rendering: headless screen tree rendering is included; native Canvas/DOM/GPU presentation is supplied by the host.

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
