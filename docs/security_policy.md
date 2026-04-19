# Security Policy

## OSC 52 Clipboard

OSC 52 reads and writes are controlled by terminal options. Keep `clipboard_enabled` false for untrusted remote output, set `clipboard_max_bytes`, and prefer explicit `clipboard_read_handler` and `clipboard_write_handler` hooks so applications can prompt or deny requests.

## Hyperlinks

OSC 8 links are stored as cell metadata and emitted through events. Treat link activation as a host application decision. Validate URI schemes before opening external applications.

## Images

Sixel and iTerm2 image payloads are parsed and tracked as terminal metadata. Rendering layers should enforce size, memory, and MIME policies before decoding or displaying image data.

## PTY Spawn

PTY commands inherit process privileges from the host process. Pass an explicit command, args, environment, working directory, and process-group policy. Do not forward untrusted browser input directly into a privileged shell.

## BrowserBridge

Use origin checks, message size limits, rate limits, heartbeat timeouts, attach policies, and authentication hooks for deployed WebSocket bridges. Prefer TLS termination and per-session authorization in front of the bridge.
