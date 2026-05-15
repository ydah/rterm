(function (global) {
  "use strict";

  const DEFAULT_COLS = 80;
  const DEFAULT_ROWS = 24;
  const NAV_KEYS = new Set([
    "ArrowUp",
    "ArrowDown",
    "ArrowLeft",
    "ArrowRight",
    "Backspace",
    "Delete",
    "Enter",
    "Escape",
    "Home",
    "End",
    "PageUp",
    "PageDown",
    "Tab"
  ]);

  class RTermBrowserAdapter extends EventTarget {
    constructor(target, options = {}) {
      super();
      this.element = typeof target === "string" ? document.querySelector(target) : target;
      if (!this.element) throw new Error("RTermBrowserAdapter target is required");

      this.options = options;
      this.sessionId = options.sessionId || null;
      this.clientId = options.clientId || randomId();
      this.socket = null;
      this.cols = options.cols || DEFAULT_COLS;
      this.rows = options.rows || DEFAULT_ROWS;
      this.cell = { width: 9, height: 18 };
      this.binary = false;
      this.pendingText = "";
      this.canvas = options.canvas || null;
      this.webglRenderer = null;
      this.mount();
      this.bindInput();
      this.bindResize();
      this.bindRendererSurface();
      if (options.url || options.socket) this.connect(options.url || options.socket);
    }

    mount() {
      this.element.classList.add("rterm-browser");
      this.element.tabIndex = this.element.tabIndex < 0 ? 0 : this.element.tabIndex;
      this.screen = document.createElement("div");
      this.screen.className = "rterm-browser-screen";
      this.screen.setAttribute("role", "grid");
      this.textarea = document.createElement("textarea");
      this.textarea.className = "rterm-browser-textarea";
      this.textarea.setAttribute("aria-label", "Terminal input");
      this.textarea.autocapitalize = "off";
      this.textarea.autocomplete = "off";
      this.textarea.spellcheck = false;
      this.live = document.createElement("div");
      this.live.className = "rterm-browser-live";
      this.live.setAttribute("role", "status");
      this.live.setAttribute("aria-live", "polite");
      this.measureNode = document.createElement("span");
      this.measureNode.className = "rterm-browser-measure";
      this.measureNode.textContent = "W".repeat(20);
      const children = [this.screen, this.textarea, this.live, this.measureNode];
      if (this.webglRequested()) {
        this.canvas = this.canvas || document.createElement("canvas");
        this.canvas.classList.add("rterm-browser-webgl");
        if (!this.options.canvas || this.canvas.parentNode === this.element || !this.canvas.parentNode) children.unshift(this.canvas);
      }
      this.element.replaceChildren(...children);
      this.measure();
    }

    connect(urlOrSocket) {
      this.socket = typeof urlOrSocket === "string" ? new WebSocket(urlOrSocket) : urlOrSocket;
      this.socket.addEventListener("open", () => {
        this.dispatch("open");
        if (this.options.binary) this.send("negotiate", { binary: true });
        if (this.sessionId) {
          this.send("attach_session", { clientId: this.clientId }, this.sessionId);
        } else {
          this.send("create_session", { cols: this.cols, rows: this.rows, terminalOptions: this.options.terminalOptions || {} });
        }
      });
      this.socket.addEventListener("message", (event) => this.decodeMessage(event.data));
      this.socket.addEventListener("close", () => this.dispatch("close"));
      this.socket.addEventListener("error", (event) => this.dispatch("error", { event }));
      return this;
    }

    send(type, payload = {}, sessionId = this.sessionId) {
      const message = { type, payload };
      if (sessionId) message.session_id = sessionId;
      if (this.socket && this.socket.readyState === WebSocket.OPEN) {
        this.socket.send(JSON.stringify(message));
      }
      return message;
    }

    sendHostEvent(payload) {
      return this.send("host_event", payload);
    }

    decodeMessage(data) {
      if (data instanceof Blob) {
        data.text().then((text) => this.handleMessage(JSON.parse(text)));
        return;
      }
      if (data instanceof ArrayBuffer) {
        this.handleBinary(new Uint8Array(data));
        return;
      }
      this.handleMessage(JSON.parse(data));
    }

    handleBinary(bytes) {
      const text = new TextDecoder().decode(bytes.slice(1));
      this.handleMessage({ type: "output", session_id: this.sessionId, payload: { data: text } });
    }

    handleMessage(message) {
      const payload = message.payload || {};
      if (message.session_id || message.sessionId) this.sessionId = message.session_id || message.sessionId;

      switch (message.type) {
        case "session_created":
          this.send("attach_session", { clientId: this.clientId }, this.sessionId);
          break;
        case "session_attached":
        case "session_resumed":
          this.applySnapshot(payload);
          this.resizeToElement();
          break;
        case "host_command":
          this.applyCommand(payload.command || payload);
          break;
        case "output":
          this.appendPlainText(payload.data || "");
          break;
        case "negotiated":
          this.binary = payload.binary === true;
          break;
        case "error":
          this.dispatch("error", payload);
          break;
      }
      this.dispatch("message", { message });
    }

    applySnapshot(payload) {
      const commands = payload.host_commands || payload.hostCommands || [];
      commands.forEach((command) => this.applyCommand(command));
    }

    applyCommand(command) {
      if (!command) return;
      const payload = command.payload || {};
      switch (command.type) {
        case "screen":
          this.renderScreen(payload.screen);
          break;
        case "accessibility":
        case "screen_reader":
          this.updateLiveRegion(payload);
          break;
        case "clipboard_write":
          this.writeClipboard(payload.decoded || "");
          break;
        case "clipboard_read_request":
          this.readClipboard(payload.selection || "c");
          break;
        case "font_load":
          this.loadFont(payload).then(() => this.resizeToElement());
          break;
        case "renderer_change":
          this.dispatch("rendererchange", payload);
          break;
      }
      this.dispatch("command", { command });
    }

    renderScreen(screen) {
      if (!screen || !Array.isArray(screen.rows)) return;
      this.cols = screen.cols || this.cols;
      this.rows = screen.rows_count || screen.rowsCount || this.rows;
      this.screen.setAttribute("aria-colcount", String(this.cols));
      this.screen.setAttribute("aria-rowcount", String(this.rows));
      const fragment = document.createDocumentFragment();
      screen.rows.forEach((row) => fragment.appendChild(this.renderRow(row)));
      this.screen.replaceChildren(fragment);
      if (this.webglRenderer) this.webglRenderer.render(screen, this.cell, getComputedStyle(this.element));
    }

    renderRow(row) {
      const element = document.createElement("div");
      element.className = "rterm-browser-row";
      element.setAttribute("role", "row");
      element.dataset.row = String(row.row || 0);
      (row.cells || []).forEach((cell) => element.appendChild(this.renderCell(cell)));
      return element;
    }

    renderCell(cell) {
      const element = document.createElement("span");
      element.className = "rterm-browser-cell";
      element.setAttribute("role", "gridcell");
      element.dataset.col = String(cell.col || 0);
      element.textContent = cell.char || " ";
      const colors = cell.colors || {};
      if (colors.foreground) element.style.color = colors.foreground;
      if (colors.background) element.style.backgroundColor = colors.background;
      const attributes = cell.attributes || {};
      if (attributes.bold) element.style.fontWeight = "700";
      if (attributes.italic) element.style.fontStyle = "italic";
      if (attributes.underline) element.style.textDecoration = "underline";
      return element;
    }

    appendPlainText(text) {
      if (!text) return;
      this.pendingText = (this.pendingText + text).slice(-8192);
      this.screen.textContent = this.pendingText;
    }

    bindInput() {
      this.element.addEventListener("focus", () => {
        this.textarea.focus();
        this.sendHostEvent({ type: "focus" });
      });
      this.textarea.addEventListener("blur", () => this.sendHostEvent({ type: "blur" }));
      this.textarea.addEventListener("beforeinput", (event) => {
        if (event.inputType === "insertText" && event.data) this.send("input", { data: event.data });
      });
      this.textarea.addEventListener("paste", (event) => {
        event.preventDefault();
        const text = event.clipboardData ? event.clipboardData.getData("text/plain") : "";
        this.sendHostEvent({ type: "paste", data: text });
      });
      this.textarea.addEventListener("compositionstart", (event) => this.sendHostEvent({ type: "composition_start", data: event.data || "" }));
      this.textarea.addEventListener("compositionupdate", (event) => this.sendHostEvent({ type: "composition_update", data: event.data || "" }));
      this.textarea.addEventListener("compositionend", (event) => this.sendHostEvent({ type: "composition_end", data: event.data || "" }));
      this.textarea.addEventListener("keydown", (event) => this.handleKey(event));
      this.screen.addEventListener("mousedown", (event) => this.handlePointer(event, "press"));
      this.screen.addEventListener("mouseup", (event) => this.handlePointer(event, "release"));
      this.screen.addEventListener("mousemove", (event) => {
        if (event.buttons) this.handlePointer(event, "motion");
      });
      this.screen.addEventListener("wheel", (event) => this.handleWheel(event), { passive: false });
    }

    handleKey(event) {
      if (!NAV_KEYS.has(event.key)) return;
      event.preventDefault();
      this.sendHostEvent({ type: "key", key: keyName(event.key), modifiers: modifiers(event) });
    }

    handlePointer(event, action) {
      const point = this.eventCell(event);
      this.sendHostEvent({
        type: "mouse",
        action,
        button: mouseButton(event),
        col: point.col,
        row: point.row,
        pixelCol: event.offsetX,
        pixelRow: event.offsetY,
        modifiers: modifiers(event)
      });
    }

    handleWheel(event) {
      event.preventDefault();
      const point = this.eventCell(event);
      this.sendHostEvent({ type: "wheel", amount: event.deltaY > 0 ? 1 : -1, col: point.col, row: point.row, modifiers: modifiers(event) });
    }

    eventCell(event) {
      const rect = this.screen.getBoundingClientRect();
      return {
        col: clamp(Math.floor((event.clientX - rect.left) / this.cell.width), 0, this.cols - 1),
        row: clamp(Math.floor((event.clientY - rect.top) / this.cell.height), 0, this.rows - 1)
      };
    }

    bindResize() {
      if (!("ResizeObserver" in global)) return;
      this.resizeObserver = new ResizeObserver(() => this.resizeToElement());
      this.resizeObserver.observe(this.element);
    }

    resizeToElement() {
      this.measure();
      const rect = this.element.getBoundingClientRect();
      const cols = Math.max(1, Math.floor(rect.width / this.cell.width));
      const rows = Math.max(1, Math.floor(rect.height / this.cell.height));
      if (this.webglRenderer) this.webglRenderer.resize(rect.width, rect.height);
      if (cols === this.cols && rows === this.rows) return;
      this.cols = cols;
      this.rows = rows;
      this.send("resize", { cols, rows, cellWidth: this.cell.width, cellHeight: this.cell.height });
    }

    measure() {
      const rect = this.measureNode.getBoundingClientRect();
      this.cell = {
        width: rect.width > 0 ? rect.width / 20 : this.cell.width,
        height: rect.height > 0 ? rect.height : this.cell.height
      };
      return this.cell;
    }

    bindRendererSurface() {
      const canvas = this.canvas;
      if (!canvas || !canvas.addEventListener) return;
      if (this.webglRequested() && global.RTermWebGLRenderer) {
        try {
          this.webglRenderer = new global.RTermWebGLRenderer(canvas, {
            onContextLoss: () => this.sendHostEvent({ type: "renderer_context_loss", reason: "webglcontextlost" }),
            onContextRestore: () => this.sendHostEvent({ type: "renderer_context_restore" })
          });
          if (this.webglRenderer.ready) {
            this.element.classList.add("is-webgl");
            return;
          }
        } catch (error) {
          this.dispatch("renderererror", { error });
        }
      }
      canvas.addEventListener("webglcontextlost", (event) => {
        event.preventDefault();
        this.sendHostEvent({ type: "renderer_context_loss", reason: "webglcontextlost" });
      });
      canvas.addEventListener("webglcontextrestored", () => this.sendHostEvent({ type: "renderer_context_restore" }));
    }

    async loadFont(face) {
      if (!("FontFace" in global) || !document.fonts || !face.family || !face.source) return;
      const font = new FontFace(face.family, face.source, {
        style: face.style || "normal",
        weight: String(face.weight || "normal"),
        stretch: face.stretch || "normal",
        display: face.display || "swap"
      });
      document.fonts.add(font);
      await font.load();
    }

    async readClipboard(selection) {
      if (!navigator.clipboard || !navigator.clipboard.readText) return;
      const text = await navigator.clipboard.readText();
      this.sendHostEvent({ type: "clipboard_text", selection, text });
    }

    async writeClipboard(text) {
      if (navigator.clipboard && navigator.clipboard.writeText) await navigator.clipboard.writeText(text);
    }

    webglRequested() {
      return this.options.renderer === "webgl" || this.options.webgl === true || !!this.options.canvas;
    }

    updateLiveRegion(payload) {
      const text = payload.text || payload.last_announcement || payload.lastAnnouncement || "";
      if (text) this.live.textContent = text;
    }

    dispatch(type, detail = {}) {
      this.dispatchEvent(new CustomEvent(type, { detail }));
    }

    dispose() {
      if (this.resizeObserver) this.resizeObserver.disconnect();
      if (this.webglRenderer) this.webglRenderer.destroy();
      if (this.socket) this.socket.close();
      this.element.replaceChildren();
    }
  }

  function modifiers(event) {
    const result = [];
    if (event.shiftKey) result.push("shift");
    if (event.altKey) result.push("alt");
    if (event.ctrlKey) result.push("ctrl");
    if (event.metaKey) result.push("meta");
    return result;
  }

  function keyName(key) {
    return key.replace(/^Arrow/, "").toLowerCase();
  }

  function mouseButton(event) {
    return ["left", "middle", "right"][event.button] || "left";
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function randomId() {
    return Math.random().toString(36).slice(2);
  }

  global.RTermBrowserAdapter = RTermBrowserAdapter;
})(typeof window !== "undefined" ? window : globalThis);
