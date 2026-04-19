# Renderer And Font Measurement Scope

rterm is a headless terminal core. It owns parsing, buffer state, selection, search, serialization, PTY integration, and bridge protocol behavior.

Renderer-specific responsibilities stay out of core:

- Font loading and fallback selection.
- Character cell measurement in a browser or native UI.
- Canvas, DOM, GPU, or terminal widget drawing.
- Cursor animation timing.
- Pixel-level image decoding and scaling.
- Accessibility presentation beyond emitted narration events.

Use `RTerm::Services::CHAR_SIZE_SERVICE` to pass measured cell dimensions into integrations, and `Terminal#cell_colors` / `Terminal#cursor_info` to resolve renderer-facing policy from terminal options.
