(function (global) {
  "use strict";

  const DEFAULT_COLS = 80;
  const DEFAULT_ROWS = 24;
  const TERMINAL_KEYS = new Set([
    "ArrowUp",
    "ArrowDown",
    "ArrowLeft",
    "ArrowRight",
    "Backspace",
    "Delete",
    "Insert",
    "Enter",
    "Escape",
    "Home",
    "End",
    "PageUp",
    "PageDown",
    "Tab",
    "F1",
    "F2",
    "F3",
    "F4",
    "F5",
    "F6",
    "F7",
    "F8",
    "F9",
    "F10",
    "F11",
    "F12"
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
      this.lastScreen = null;
      this.selection = null;
      this.cursor = null;
      this.pointerSelectionStart = null;
      this.title = "";
      this.iconName = "";
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
      this.cols = payload.cols || this.cols;
      this.rows = payload.rows || this.rows;
      this.updateTitle(payload);
      const commands = payload.host_commands || payload.hostCommands || [];
      commands.forEach((command) => this.applyCommand(command));
    }

    applyCommand(command) {
      if (!command) return;
      const payload = Object.prototype.hasOwnProperty.call(command, "payload") ? command.payload : {};
      switch (command.type) {
        case "activate":
        case "mount":
        case "dispose":
          this.dispatch(command.type, payload || {});
          break;
        case "screen":
          this.renderScreen((payload && payload.screen) || payload);
          break;
        case "render":
          this.updateLiveRegion(payload || {});
          this.dispatch("render", payload || {});
          break;
        case "resize":
          this.applyResize(payload || {});
          break;
        case "scroll":
          this.dispatch("scroll", payload || {});
          break;
        case "selection_change":
          this.updateSelection(payload);
          break;
        case "title":
          this.updateTitle(payload || {});
          break;
        case "bell":
          this.handleBell(payload || {});
          break;
        case "raster":
          this.renderRaster((payload && payload.frame) || payload);
          break;
        case "accessibility":
        case "screen_reader":
          this.updateLiveRegion(payload || {});
          break;
        case "clipboard_write":
          this.writeClipboard((payload && payload.decoded) || "");
          break;
        case "clipboard_read_request":
          this.readClipboard((payload && payload.selection) || "c");
          break;
        case "clipboard_response":
          this.dispatch("clipboardresponse", payload || {});
          break;
        case "font_load":
          this.loadFont(payload || {}).then(() => this.resizeToElement());
          break;
        case "font_measure":
        case "font_relayout":
          this.measure();
          this.resizeToElement();
          break;
        case "renderer_change":
          this.dispatch("rendererchange", payload || {});
          break;
        case "renderer_context_loss":
          this.dispatch("renderercontextloss", payload || {});
          break;
        case "renderer_context_restore":
          this.dispatch("renderercontextrestore", payload || {});
          break;
      }
      this.dispatch("command", { command });
    }

    renderScreen(screen) {
      if (!screen || !Array.isArray(screen.rows)) return;
      this.lastScreen = screen;
      this.cursor = screen.cursor || this.cursor;
      this.cols = screen.cols || this.cols;
      this.rows = screen.rows_count || screen.rowsCount || this.rows;
      this.screen.setAttribute("aria-colcount", String(this.cols));
      this.screen.setAttribute("aria-rowcount", String(this.rows));
      const fragment = document.createDocumentFragment();
      screen.rows.forEach((row) => fragment.appendChild(this.renderRow(row)));
      this.screen.replaceChildren(fragment);
      this.applyDomSelection();
      if (this.webglRenderer) this.webglRenderer.render(screen, this.cell, getComputedStyle(this.element), this.renderState());
    }

    renderRow(row) {
      const element = document.createElement("div");
      element.className = "rterm-browser-row";
      element.setAttribute("role", "row");
      const rowIndex = row.row || 0;
      element.dataset.row = String(rowIndex);
      if (row.absolute_row != null || row.absoluteRow != null) element.dataset.absoluteRow = String(row.absolute_row || row.absoluteRow);
      (row.cells || []).forEach((cell) => element.appendChild(this.renderCell(cell, rowIndex)));
      return element;
    }

    renderCell(cell, row) {
      const link = cell.link || {};
      const uri = link.uri || link.url || "";
      const element = uri && safeLinkUri(uri) ? document.createElement("a") : document.createElement("span");
      element.className = "rterm-browser-cell";
      element.setAttribute("role", "gridcell");
      element.dataset.col = String(cell.col || 0);
      element.dataset.width = String(cell.width || 1);
      element.textContent = cell.char || " ";
      if ((cell.width || 1) > 1) element.style.width = `${cell.width}ch`;
      if (uri) {
        element.classList.add("is-link");
        element.dataset.linkUri = uri;
        if (element.tagName === "A") {
          element.href = uri;
          element.target = "_blank";
          element.rel = "noreferrer noopener";
        }
      }
      const colors = cell.colors || {};
      if (colors.foreground) element.style.color = colors.foreground;
      if (colors.background) element.style.backgroundColor = colors.background;
      this.applyCellAttributes(element, cell);
      if (this.isCursorCell(cell, row)) element.classList.add("is-cursor");
      return element;
    }

    applyCellAttributes(element, cell) {
      const attributes = cell.attributes || {};
      const decorations = [];
      if (attributes.bold) element.style.fontWeight = "700";
      if (attributes.italic) element.style.fontStyle = "italic";
      if (attributes.dim) element.classList.add("is-dim");
      if (attributes.inverse) element.classList.add("is-inverse");
      if (attributes.invisible) element.classList.add("is-invisible");
      if (attributes.blink) element.classList.add("is-blinking");
      if (attributes.underline || cell.link) decorations.push("underline");
      if (attributes.strikethrough) decorations.push("line-through");
      if (attributes.overline) decorations.push("overline");
      if (decorations.length > 0) element.style.textDecorationLine = decorations.join(" ");
    }

    appendPlainText(text) {
      if (!text) return;
      this.pendingText = (this.pendingText + text).slice(-8192);
      this.screen.textContent = this.pendingText;
    }

    applyResize(payload) {
      if (payload.cols || payload.columns) this.cols = payload.cols || payload.columns;
      if (payload.rows) this.rows = payload.rows;
      if (payload.cell_width || payload.cellWidth || payload.cell_height || payload.cellHeight) {
        this.cell = {
          width: payload.cell_width || payload.cellWidth || this.cell.width,
          height: payload.cell_height || payload.cellHeight || this.cell.height
        };
      }
      this.dispatch("resize", { cols: this.cols, rows: this.rows, cell: this.cell });
      if (this.webglRenderer && this.lastScreen) this.webglRenderer.render(this.lastScreen, this.cell, getComputedStyle(this.element), this.renderState());
    }

    updateSelection(payload) {
      this.selection = payload && !payload.empty ? payload : null;
      this.applyDomSelection();
      if (this.webglRenderer && this.lastScreen) this.webglRenderer.render(this.lastScreen, this.cell, getComputedStyle(this.element), this.renderState());
      this.dispatch("selectionchange", { selection: this.selection });
    }

    updateTitle(payload) {
      this.title = payload.title || payload.windowTitle || payload.window_title || this.title;
      this.iconName = payload.icon_name || payload.iconName || this.iconName;
      if (this.title) this.element.setAttribute("aria-label", this.title);
      this.dispatch("titlechange", { title: this.title, iconName: this.iconName });
    }

    handleBell(payload) {
      this.element.classList.add("is-bell");
      global.setTimeout(() => this.element.classList.remove("is-bell"), 120);
      this.dispatch("bell", payload);
    }

    renderRaster(frame) {
      if (!frame) return;
      if (this.webglRenderer && this.webglRenderer.renderRaster) this.webglRenderer.renderRaster(frame);
      this.dispatch("raster", { frame });
    }

    renderState() {
      return {
        cursor: this.cursor,
        selection: this.selection
      };
    }

    applyDomSelection() {
      this.screen.querySelectorAll(".is-selected").forEach((element) => element.classList.remove("is-selected"));
      if (!this.selection) return;

      this.screen.querySelectorAll(".rterm-browser-cell").forEach((element) => {
        const row = Number(element.parentElement.dataset.row || 0);
        const col = Number(element.dataset.col || 0);
        const width = Number(element.dataset.width || 1);
        if (this.isSelectedCell({ col, width }, row)) element.classList.add("is-selected");
      });
    }

    isSelectedCell(cell, row) {
      const selection = this.selection;
      if (!selection) return false;

      const range = normalizedSelectionRange(selection);
      if (!range) return false;

      const col = Number(cell.col || 0);
      const width = Math.max(1, Number(cell.width || 1));
      if (isRectangleSelection(selection)) {
        return row >= range.start.y && row <= range.end.y && col + width > range.start.x && col < range.end.x;
      }

      if (row < range.start.y || row > range.end.y) return false;
      if (range.start.y === range.end.y) return col + width > range.start.x && col < range.end.x;
      if (row === range.start.y) return col + width > range.start.x;
      if (row === range.end.y) return col < range.end.x;
      return true;
    }

    isCursorCell(cell, row) {
      if (!this.cursor) return false;

      return Number(this.cursor.row || 0) === row && Number(this.cursor.col || 0) === Number(cell.col || 0);
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
      this.screen.addEventListener("click", (event) => this.handleClickSelection(event));
      this.screen.addEventListener("contextmenu", (event) => this.handleContextMenu(event));
      this.screen.addEventListener("mousedown", (event) => this.handlePointer(event, "press"));
      this.screen.addEventListener("mouseup", (event) => this.handlePointer(event, "release"));
      this.screen.addEventListener("mousemove", (event) => {
        if (event.buttons) this.handlePointer(event, "motion");
      });
      this.screen.addEventListener("wheel", (event) => this.handleWheel(event), { passive: false });
    }

    handleKey(event) {
      if (event.isComposing) return;
      const key = terminalKeyName(event);
      const modifiedPrintable = event.key && event.key.length === 1 && (event.altKey || event.ctrlKey || event.metaKey);
      if (!key && !modifiedPrintable) return;
      event.preventDefault();
      this.sendHostEvent({
        type: "key",
        key: key || event.key,
        code: event.code,
        keyCode: event.keyCode,
        text: modifiedPrintable && !event.ctrlKey ? event.key : undefined,
        modifiers: modifiers(event)
      });
    }

    handlePointer(event, action) {
      const point = this.eventCell(event);
      if (action === "press" && event.button === 0) this.pointerSelectionStart = point;
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
      if (action === "release" && event.button === 0) this.handleDragSelection(point, event);
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

    handleClickSelection(event) {
      const link = event.target.closest(".rterm-browser-cell.is-link");
      if (link) this.dispatch("linkactivate", { uri: link.dataset.linkUri, event });
      if (event.button !== 0 || event.detail < 2) return;
      const point = this.eventCell(event);
      this.sendHostEvent({
        type: "selection",
        mode: "click",
        col: point.col,
        row: point.row,
        clickCount: event.detail,
        button: "left"
      });
    }

    handleDragSelection(point, event) {
      const start = this.pointerSelectionStart;
      this.pointerSelectionStart = null;
      if (!start || (start.col === point.col && start.row === point.row)) return;

      this.sendHostEvent({
        type: "selection",
        mode: event.altKey ? "rectangle" : "linear",
        startCol: start.col,
        startRow: start.row,
        endCol: point.col,
        endRow: point.row
      });
    }

    handleContextMenu(event) {
      event.preventDefault();
      const point = this.eventCell(event);
      this.sendHostEvent({
        type: "context_menu",
        col: point.col,
        row: point.row,
        clientX: event.clientX,
        clientY: event.clientY,
        pageX: event.pageX,
        pageY: event.pageY,
        modifiers: modifiers(event)
      });
      this.dispatch("contextmenu", { col: point.col, row: point.row, event });
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

  function terminalKeyName(event) {
    if (event.code && event.code.startsWith("Numpad")) return keypadKeyName(event.code);
    if (!TERMINAL_KEYS.has(event.key)) return null;
    return event.key
      .replace(/^Arrow/, "")
      .replace(/^Page/, "page_")
      .replace(/([a-z])([A-Z])/g, "$1_$2")
      .toLowerCase();
  }

  function keypadKeyName(code) {
    const name = code.replace(/^Numpad/, "").toLowerCase();
    if (name.match(/^[0-9]$/)) return `keypad_${name}`;
    return {
      enter: "keypad_enter",
      add: "keypad_add",
      subtract: "keypad_subtract",
      multiply: "keypad_multiply",
      divide: "keypad_divide",
      decimal: "keypad_decimal"
    }[name] || null;
  }

  function normalizedSelectionRange(selection) {
    const start = selection.start || selection.start_pos || selection.startPos;
    const end = selection.end || selection.end_pos || selection.endPos;
    if (!start || !end) return rangeFromSelectionShape(selection.selection || selection);

    const startPoint = normalizePoint(start);
    const endPoint = normalizePoint(end);
    if (startPoint.y > endPoint.y || (startPoint.y === endPoint.y && startPoint.x > endPoint.x)) {
      return { start: endPoint, end: startPoint };
    }
    return { start: startPoint, end: endPoint };
  }

  function normalizePoint(point) {
    return {
      x: Number(point.x == null ? point.col || point.column || 0 : point.x),
      y: Number(point.y == null ? point.row || 0 : point.y)
    };
  }

  function rangeFromSelectionShape(shape) {
    if (!shape) return null;
    const type = String(shape.type || "");
    if (type === "rectangle") {
      const startColumn = Number(shape.start_column || shape.startColumn || 0);
      const endColumn = Number(shape.end_column || shape.endColumn || startColumn);
      const startRow = Number(shape.start_row || shape.startRow || 0);
      const endRow = Number(shape.end_row || shape.endRow || startRow);
      return {
        start: { x: Math.min(startColumn, endColumn), y: Math.min(startRow, endRow) },
        end: { x: Math.max(startColumn, endColumn) + 1, y: Math.max(startRow, endRow) }
      };
    }
    if (type === "linear") {
      const column = Number(shape.column || shape.col || 0);
      const row = Number(shape.row || 0);
      return { start: { x: column, y: row }, end: { x: column + Number(shape.length || 0), y: row } };
    }
    return null;
  }

  function isRectangleSelection(selection) {
    const shape = selection.selection || selection;
    return String(shape.type || "") === "rectangle";
  }

  function safeLinkUri(uri) {
    return /^(https?:|mailto:)/i.test(String(uri));
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
