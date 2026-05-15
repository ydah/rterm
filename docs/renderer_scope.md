# Renderer And Font Measurement Scope

rterm is a headless terminal core. It owns parsing, buffer state, selection, search, serialization, PTY integration, and bridge protocol behavior.

Renderer presentation is split between Ruby-side render products and host-side UI attachment:

- Browser or native font loading beyond registered font-face metadata.
- Browser or native cell measurement beyond `CharSizeService` estimates or supplied measurements.
- Native Canvas, DOM, GPU, or terminal widget attachment.
- Browser or native accessibility tree attachment.

Use `RTerm::Services::CHAR_SIZE_SERVICE` to pass measured cell dimensions into integrations, and `Terminal#cell_colors` / `Terminal#cursor_info` to resolve renderer-facing policy from terminal options.

Use `RTerm::Addon::WebFonts#resolve_font_family` and `#measure_cell` for Ruby-side fallback selection and estimated cell metrics. Host integrations can still supply exact measurements through `RTerm::Services::CHAR_SIZE_SERVICE`.

Use `RTerm::Addon::ScreenRenderer` when a Ruby-side render tree is needed. It renders visible rows into headless elements, keeps a text snapshot, and exposes an accessibility tree that host integrations can present through their UI toolkit.

Use `RTerm::Addon::HtmlRenderer` when HTML and ARIA output is needed. It renders escaped terminal cells, row and cell roles, live-region text, and a standalone document option.

Use `RTerm::Addon::RasterRenderer` when a Ruby-side pixel frame is needed. It renders cells into an RGBA buffer, draws built-in bitmap text masks, advances cursor blink state, composites decoded Sixel, PNG, GIF, and JPEG images, including four-component, 12-bit DCT, and up to 16-bit lossless color data, presents unsupported JPEG frame data as a deterministic raster preview, and can export a PPM image for tooling.

Use `RTerm::Addon::HostIntegration` when a browser or native layer needs a stable command stream. It forwards mount, input, clipboard, font measurement, renderer, accessibility, and resize events, and it accepts host-originated key, mouse, paste, composition, viewport, and clipboard responses.

Use `RTerm::BrowserAdapter` to serve the bundled browser-side JavaScript and CSS. The adapter connects to BrowserBridge WebSockets, renders `screen` commands into DOM rows and cells or an optional WebGL/2D canvas, applies cursor, links, and selection state, handles raster frames when requested, forwards keyboard, pointer, link, selection, paste, composition, clipboard, context menu, and resize events, measures character cells with browser layout, loads registered web fonts, mirrors accessibility trees into an off-screen DOM surface, and reports renderer context lifecycle events.

BrowserBridge sessions always expose screen rendering and link metadata. Set `renderer: "raster"`, `renderers: ["screen", "raster"]`, or `raster: true` when creating a browser session to add raster frame commands for pixel-oriented clients.

Renderer integrations can keep their host-side state in `RTerm::Addon::Canvas` or `RTerm::Addon::WebGL` with:

- `attach_host` for the external element or view object.
- `update_viewport` for cell, pixel, and device-pixel-ratio measurements.
- `update_scrollbar` for externally rendered scrollbar state.

Image integrations can use the bundled Sixel and iTerm2 decoders, or `RTerm::Addon::Image#register_decoder` and `#render_all` to override decoding and delegate drawing to host code while keeping protocol metadata in the terminal core.

When `screen_reader_mode` is enabled, `Terminal#open` creates a headless live-region element and emits `:accessibility` snapshots. `HtmlRenderer` can turn that state into ARIA markup.
