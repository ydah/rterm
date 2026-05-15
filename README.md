# RTerm

RTerm is a headless terminal emulator library for Ruby. It parses ANSI/VT
streams, owns terminal state, and exposes PTY, rendering, image, and browser
bridge APIs without forcing a native UI.

## Current Scope

- Terminal core: buffer state, scrollback, reflow, selection, mouse reporting,
  modes, OSC, DCS, colors, hyperlinks, clipboard policy, and window operations.
- Process integration: Unix PTY support and a Windows ConPTY boundary.
- Rendering: screen trees, HTML/ARIA output, RGBA raster frames, renderer
  lifecycle state, and browser-side DOM/WebGL assets.
- Images: Sixel and iTerm2 image payload tracking with PNG, GIF, and JPEG
  decoding paths.
- BrowserBridge: WebSocket session transport with resume, attach policies,
  rate limits, heartbeats, origin checks, and binary frames.
- Addons: search, serialization, clipboard, links, fonts, Unicode widths,
  graphemes, ligatures, progress, images, and host integration.

## Requirements

- Ruby 3.2 or later
- `faye-websocket` for BrowserBridge WebSocket deployments
- npm 9 or later when packaging browser adapter assets

## Installation

```ruby
# Gemfile
gem "rterm"
gem "faye-websocket" # only for BrowserBridge WebSocket servers
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

## Common Usage

### Terminal State

```ruby
term.write("open https://example.com\r\n")
term.select_url(8, 0)
puts term.selection

cell = term.buffer.active.get_line(0).get_cell(0)
puts term.cell_colors(cell)
puts term.cursor_info(active: false)
```

Useful options can be passed in snake_case or camelCase:

```ruby
term = RTerm::Terminal.new(
  reflowCursorLine: true,
  scrollOnEraseInDisplay: true,
  ignoreBracketedPasteMode: true
)
```

### Addons

```ruby
search = RTerm::Addon::Search.new
term.load_addon(search)
term.write("error: failed\r\nerror: retrying")
puts search.find_all("error").length # => 2

serializer = RTerm::Addon::Serialize.new
term.load_addon(serializer)
snapshot = serializer.snapshot(scrollback: 100)

links = RTerm::Addon::WebLinks.new
term.load_addon(links)
term.write("open https://example.com")
links.open_link(links.find_links.first)
```

### Rendering

```ruby
screen = RTerm::Addon::ScreenRenderer.new
term.load_addon(screen)
puts screen.text
puts screen.accessibility_tree[:children].first[:text]

html = RTerm::Addon::HtmlRenderer.new
term.load_addon(html)
puts html.to_html

raster = RTerm::Addon::RasterRenderer.new(cell_width: 8, cell_height: 16)
term.load_addon(raster)
File.write("terminal.ppm", raster.to_ppm)
```

Renderer lifecycle addons keep host renderer state close to terminal state:

```ruby
renderer = RTerm::Addon::WebGL.new
term.load_addon(renderer)

renderer.attach_host(:canvas, viewport: { cellWidth: 9, cellHeight: 18 })
renderer.update_scrollbar(visible: true, width: 12)
renderer.on_context_loss { |event| warn event[:reason] }
```

### Images

```ruby
images = RTerm::Addon::Image.new
term.load_addon(images)

# After terminal output emits an image payload:
term.write("\ePqABCDEF\e\\")
image = images.by_protocol(:sixel).first
decoded = images.decode(image) if image
puts decoded[:result][:format] if decoded
```

### PTY

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

Windows hosts can provide or configure a ConPTY backend:

```ruby
conpty = RTerm::ConPTY.new(command: "cmd.exe", cols: 80, rows: 24)
conpty.on_data { |data| term.write(data) }
conpty.kill(:TERM, group: true) if conpty.process_group_enabled?

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

BrowserBridge production servers should start from secure defaults:

```ruby
RTerm::BrowserBridge::WebSocketServer.configure_secure_defaults do |config|
  config.allowed_origins = ["https://your-app.example"]
  config.authenticator = lambda do |message|
    payload = message[:payload] || message["payload"] || {}
    token = payload[:token] || payload["token"]
    token == ENV.fetch("RTERM_BRIDGE_TOKEN")
  end
end
```

The bundled browser adapter can mount a BrowserBridge session in a page:

```ruby
[
  RTerm::BrowserAdapter.style_tag,
  %(<div id="terminal" style="height: 480px"></div>),
  RTerm::BrowserAdapter.script_tag,
  %(<script>new RTermBrowserAdapter("#terminal", { url: "wss://your-app.example/terminal", renderer: "webgl", raster: true });</script>)
]
```

The same browser adapter assets can be consumed from JavaScript tooling:

```js
import RTermBrowserAdapter, { RTermWebGLRenderer } from "rterm-browser-adapter";
import "rterm-browser-adapter/style.css";

new RTermBrowserAdapter("#terminal", {
  url: "wss://your-app.example/terminal",
  renderer: "webgl",
  raster: true
});
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
| `Image` | Track, decode, filter, and dispatch Sixel, PNG, GIF, and JPEG payloads. |
| `Ligatures` | Compute character join ranges. |
| `Unicode11`, `UnicodeGraphemes` | Switch width providers and measure grapheme clusters. |
| `WebFonts` | Register font faces, expose CSS, estimate cells, and trigger relayout events. |
| `WebLinks` | Detect and activate links with provider hooks. |
| `HostIntegration` | Bridge host mount, input, clipboard, font, renderer, and accessibility events. |
| `ScreenRenderer`, `HtmlRenderer`, `RasterRenderer` | Produce screen trees, HTML/ARIA output, and RGBA frames. |
| `Canvas`, `WebGL` | Track renderer lifecycle and cache state. |

## Operational Notes

- `RTerm::Pty` is available on Unix-like systems.
- `RTerm::ConPTY` defines the Windows process boundary, uses the bundled native
  backend on Windows, and reports group termination support when available.
- Keep BrowserBridge origins, message size limits, rate limits, and heartbeats
  enabled in production.
- Disable clipboard handling for untrusted remote output with
  `clipboard_enabled: false`.
- Do not connect untrusted browser input directly to a privileged shell.
- Validate URI schemes before activating OSC 8 hyperlinks.

## Examples

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
npm pack --dry-run
```

Strict integration checks require external terminal tools and browser automation:

```bash
bundle exec rake e2e:strict
```

Set `RTERM_BROWSER_E2E=1` to require the Playwright browser smoke in local runs.
Benchmarks live under `spec/benchmarks/`.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
