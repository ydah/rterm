# RTerm

RTerm is a headless terminal emulator library for Ruby. It owns terminal state,
ANSI/VT parsing, scrollback, selection, PTY integration, rendering snapshots, and
BrowserBridge transport helpers. Native UI presentation stays in the host
application.

## Features

- ANSI/VT parser with scrollback, reflow, selection, mouse reporting, and mode state.
- OSC/DCS support for hyperlinks, clipboard policy hooks, Sixel, iTerm2 images, progress, colors, and window operations.
- PTY helpers for interactive processes, cwd/env, stdin close, pause/resume, process groups, and exit lifecycle.
- BrowserBridge protocol for WebSocket sessions with resume, attach policies, rate limits, heartbeats, origin checks, and binary frames.
- Browser adapter assets for DOM/WebGL rendering, link lifecycle, selection, input, clipboard, font measurement, resize observation, and renderer lifecycle events.
- Rendering helpers for headless element trees, RGBA raster frames, renderer lifecycle state, and image decoding.
- Addon APIs for search, serialization, clipboard, links, fonts, Unicode widths, ligatures, and renderer integrations.

## Requirements

- Ruby 3.2 or later

## Installation

```ruby
# Gemfile
gem "rterm"

# BrowserBridge Rack/WebSocket deployments also need:
gem "faye-websocket"
```

```bash
gem install rterm
```

## Quick Start

```ruby
require "rterm"

term = RTerm::Terminal.new(cols: 80, rows: 24, scrollback: 1_000)
term.write("Hello \e[1;31mWorld\e[0m!\r\n")

line = term.buffer.active.get_line(0)
puts line.to_string # => "Hello World!"
```

## Common Workflows

### Search And Serialize

```ruby
search = RTerm::Addon::Search.new
term.load_addon(search)

term.write("error: failed\r\nerror: retrying")
matches = search.find_all("error")
puts matches.length # => 2

serializer = RTerm::Addon::Serialize.new
term.load_addon(serializer)

snapshot = serializer.snapshot(scrollback: 100)

restored = RTerm::Terminal.new(cols: 80, rows: 24)
restored_serializer = RTerm::Addon::Serialize.new
restored.load_addon(restored_serializer)
restored_serializer.restore(snapshot)
```

### Links, Clipboard, And Images

```ruby
links = RTerm::Addon::WebLinks.new
term.load_addon(links)
term.write("open https://example.com")
links.open_link(links.find_links.first)

clipboard = RTerm::Addon::Clipboard.new
term.load_addon(clipboard)
clipboard.write_text("ready")
clipboard.paste

images = RTerm::Addon::Image.new
term.load_addon(images)
term.write("\ePqABCDEF\e\\")
puts images.decode(images.by_protocol(:sixel).first)[:result][:format]
```

### Rendering Snapshots

```ruby
screen = RTerm::Addon::ScreenRenderer.new
term.load_addon(screen)
term.write("hello")

puts screen.text
puts screen.accessibility_tree[:children].first[:text]

raster = RTerm::Addon::RasterRenderer.new(cell_width: 8, cell_height: 16)
term.load_addon(raster)
File.write("terminal.ppm", raster.to_ppm)

html = RTerm::Addon::HtmlRenderer.new
term.load_addon(html)
puts html.to_html
```

Renderer lifecycle addons track host-side renderer state:

```ruby
renderer = RTerm::Addon::WebGL.new
term.load_addon(renderer)

renderer.attach_host(:canvas, viewport: { cellWidth: 9, cellHeight: 18 })
renderer.update_scrollbar(visible: true, width: 12)
renderer.on_context_loss { |event| warn event[:reason] }
```

Host integration exposes a command stream for browser or native UI layers:

```ruby
host = RTerm::Addon::HostIntegration.new(transport: ->(command) {
  # send command to the UI layer
})
term.load_addon(host)
host.mount(focus: true)

host.receive(type: :resize, cols: 120, rows: 34, cellWidth: 9, cellHeight: 18)
host.receive(type: :key, key: :enter)
```

Bundled browser assets can mount that stream directly in a page:

```ruby
app = lambda do |_env|
  [
    200,
    { "content-type" => "text/html" },
    [
      RTerm::BrowserAdapter.style_tag,
      %(<div id="terminal" style="height: 480px"></div>),
      RTerm::BrowserAdapter.script_tag,
      %(<script>new RTermBrowserAdapter("#terminal", { url: "wss://your-app.example/terminal", renderer: "webgl", raster: true });</script>)
    ]
  ]
end
```

### Terminal APIs

```ruby
term.write("open https://example.com\r\n")
term.select_url(8, 0)
puts term.selection

term.write("\e[?1006h\e[?1000h")
term.mouse_event(button: :left, col: 4, row: 2)

cell = term.buffer.active.get_line(0).get_cell(0)
puts term.cell_colors(cell)
puts term.cursor_info(active: false)
```

Useful behavior options:

```ruby
term = RTerm::Terminal.new(
  reflowCursorLine: true,
  scrollOnEraseInDisplay: true,
  ignoreBracketedPasteMode: true
)
```

### Input Surface And Decorations

```ruby
term.open
term.on_textarea_input { |event| puts event[:data] }
term.on_accessibility { |event| puts event[:last_announcement] }
term.textarea.input("ls\r")

marker = term.register_marker
decoration = term.register_decoration(
  marker,
  x: 2,
  width: 8,
  className: "highlight",
  backgroundColor: "#334155"
)

decoration.on_render { |element| puts element.dataset["row"] }
term.refresh(0, term.rows - 1)
```

### PTY And ConPTY

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

```ruby
conpty = RTerm::ConPTY.new(command: "cmd.exe", cols: 80, rows: 24)
conpty.on_data { |data| term.write(data) }

RTerm::ConPTY.configure_backend(lambda { |**options| MyConPTYBackend.new(**options) })
```

### BrowserBridge

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

Production WebSocket setup:

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

## Addon Summary

| Addon | Purpose |
| --- | --- |
| `Attach` | Forward terminal input and remote output through socket-like objects. |
| `Search` | Find text, regex matches, captures, and optional decorations. |
| `Serialize` | Export ANSI replay, HTML, and structured snapshots. |
| `Fit` | Compute terminal dimensions from available space. |
| `Clipboard` | Handle text copy/paste and OSC 52 policy flows. |
| `Progress` | Track OSC 9 progress state. |
| `Image` | Track, decode, filter, and dispatch image payloads. |
| `Ligatures` | Compute character join ranges. |
| `Unicode11`, `UnicodeGraphemes` | Switch width providers and measure grapheme clusters. |
| `WebFonts` | Register font faces, resolve fallback families, estimate cells, expose CSS, and trigger relayout events. |
| `HostIntegration` | Bridge host mount, input, clipboard, font measurement, renderer, and accessibility events. |
| `ScreenRenderer`, `HtmlRenderer`, `RasterRenderer` | Produce headless render trees, HTML/ARIA output, and RGBA frames. |
| `Canvas`, `WebGL` | Track external renderer lifecycle and cache state; browser assets include a WebGL canvas renderer with cursor, links, selection, and raster frame handling. |
| `WebLinks` | Detect and activate links with provider hooks. |

## Platform Notes

- Unix PTY is supported through `RTerm::Pty`.
- Windows process integration is available through `RTerm::ConPTY` and its bundled process backend. Host backends can override native process handling.
- Headless screen trees, HTML/ARIA output, and RGBA raster rendering are included. Host applications can present these through their UI toolkit.

## Security Notes

- Disable clipboard handling for untrusted remote output with `clipboard_enabled: false`.
- Set `allowed_origins` for BrowserBridge deployments.
- Keep message size limits, rate limits, and heartbeat timeouts enabled in production.
- Do not connect untrusted browser input directly to a privileged shell.
- Validate URI schemes before activating OSC 8 hyperlinks.

## More Examples

- `examples/basic_usage.rb`
- `examples/addons.rb`
- `examples/browser_adapter.html`
- `examples/websocket_server.rb`
- `examples/browser_bridge_production.rb`

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

Benchmarks live under `spec/benchmarks/` and can be run directly with Ruby:

```bash
ruby spec/benchmarks/parser_benchmark.rb
ruby spec/benchmarks/search_benchmark.rb
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
