# Renderer And Font Measurement Scope

rterm is a headless terminal core. It owns parsing, buffer state, selection, search, serialization, PTY integration, and bridge protocol behavior.

Native renderer-specific responsibilities stay out of core:

- Font loading and fallback selection.
- Character cell measurement in a browser or native UI.
- Native Canvas, DOM, GPU, or terminal widget drawing.
- Cursor animation timing.
- Pixel-level image decoding and scaling.
- Accessibility presentation beyond emitted narration events.

Use `RTerm::Services::CHAR_SIZE_SERVICE` to pass measured cell dimensions into integrations, and `Terminal#cell_colors` / `Terminal#cursor_info` to resolve renderer-facing policy from terminal options.

Use `RTerm::Addon::ScreenRenderer` when a Ruby-side render tree is needed. It renders visible rows into headless elements, keeps a text snapshot, and exposes an accessibility tree that host integrations can present through their UI toolkit.

Renderer integrations can keep their host-side state in `RTerm::Addon::Canvas` or `RTerm::Addon::WebGL` with:

- `attach_host` for the external element or view object.
- `update_viewport` for cell, pixel, and device-pixel-ratio measurements.
- `update_scrollbar` for externally rendered scrollbar state.

Image integrations can use the bundled Sixel and iTerm2 decoders, or `RTerm::Addon::Image#register_decoder` and `#render_all` to override decoding and delegate drawing to host code while keeping protocol metadata in the terminal core.

When `screen_reader_mode` is enabled, `Terminal#open` creates a headless live-region element and emits `:accessibility` snapshots. Browser or native UI layers are still responsible for presenting that element to their accessibility tree.
