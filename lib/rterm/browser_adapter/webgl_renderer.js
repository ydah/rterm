(function (global) {
  "use strict";

  class RTermWebGLRenderer {
    constructor(canvas, options = {}) {
      this.canvas = canvas;
      this.options = options;
      this.logicalWidth = 1;
      this.logicalHeight = 1;
      this.gl = canvas.getContext("webgl2", { alpha: false }) || canvas.getContext("webgl", { alpha: false });
      this.glyphs = new Map();
      this.atlas = null;
      this.ready = !!this.gl;
      if (!this.ready) return;

      this.program = this.createProgram();
      this.position = this.gl.getAttribLocation(this.program, "a_position");
      this.texcoord = this.gl.getAttribLocation(this.program, "a_texcoord");
      this.resolution = this.gl.getUniformLocation(this.program, "u_resolution");
      this.color = this.gl.getUniformLocation(this.program, "u_color");
      this.texture = this.gl.getUniformLocation(this.program, "u_texture");
      this.buffer = this.gl.createBuffer();
      this.whiteTexture = this.createSolidTexture();
      this.createAtlas();
      this.gl.enable(this.gl.BLEND);
      this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);
      this.bindContextEvents();
    }

    render(screen, cell, style = {}, state = {}) {
      if (!this.ready || !screen || !Array.isArray(screen.rows)) return false;

      const cols = screen.cols || 80;
      const rows = screen.rows_count || screen.rowsCount || screen.rows.length;
      const width = Math.max(1, Math.ceil(cols * cell.width));
      const height = Math.max(1, Math.ceil(rows * cell.height));
      this.resize(width, height);
      this.clear(style.backgroundColor || "#0b0f14");
      screen.rows.forEach((row) => this.drawRow(row, cell, style, screen, state));
      return true;
    }

    renderRaster(frame) {
      if (!this.ready || !frame || !Array.isArray(frame.pixels)) return false;

      const width = Math.max(1, Number(frame.width || 1));
      const height = Math.max(1, Number(frame.height || 1));
      this.resize(width, height);
      const texture = this.createRasterTexture(frame, width, height);
      this.clear("#000000");
      this.drawQuad(0, 0, width, height, texture, [0, 0, 1, 1], "#ffffff");
      this.gl.deleteTexture(texture);
      return true;
    }

    resize(width, height) {
      const ratio = global.devicePixelRatio || 1;
      const pixelWidth = Math.max(1, Math.ceil(width * ratio));
      const pixelHeight = Math.max(1, Math.ceil(height * ratio));
      this.logicalWidth = Math.max(1, width);
      this.logicalHeight = Math.max(1, height);
      if (this.canvas.width !== pixelWidth) this.canvas.width = pixelWidth;
      if (this.canvas.height !== pixelHeight) this.canvas.height = pixelHeight;
      this.canvas.style.width = `${width}px`;
      this.canvas.style.height = `${height}px`;
      this.gl.viewport(0, 0, pixelWidth, pixelHeight);
    }

    clear(background) {
      const color = parseColor(background, [11, 15, 20, 255]);
      this.gl.clearColor(color[0] / 255, color[1] / 255, color[2] / 255, color[3] / 255);
      this.gl.clear(this.gl.COLOR_BUFFER_BIT);
    }

    destroy() {
      if (!this.gl) return;

      if (this.buffer) this.gl.deleteBuffer(this.buffer);
      [this.whiteTexture, this.atlas && this.atlas.texture].forEach((resource) => {
        if (resource) this.gl.deleteTexture(resource);
      });
      this.gl.deleteProgram(this.program);
      this.ready = false;
    }

    drawRow(row, cell, style, screen, state) {
      (row.cells || []).forEach((item) => this.drawCell(item, row.row || 0, cell, style, screen, state));
    }

    drawCell(cell, row, metrics, style, screen, state) {
      const x = (cell.col || 0) * metrics.width;
      const y = row * metrics.height;
      const width = Math.max(metrics.width * (cell.width || 1), 1);
      const height = Math.max(metrics.height, 1);
      const colors = cell.colors || {};
      const attrs = cell.attributes || {};
      const selected = isSelectedCell(cell, row, state.selection);
      const cursor = isCursorCell(cell, row, state.cursor || screen.cursor);
      let background = colors.background || style.backgroundColor || "#0b0f14";
      let foreground = colors.foreground || style.color || "#e5e7eb";

      if (attrs.inverse && !colors.background && !colors.foreground) {
        [background, foreground] = [foreground, background];
      }
      if (selected) {
        background = styleValue(style, "--rterm-selection-background", "#1d4ed8");
        foreground = styleValue(style, "--rterm-selection-foreground", "#ffffff");
      }
      if (cursor) {
        background = styleValue(style, "--rterm-cursor-background", "#e5e7eb");
        foreground = styleValue(style, "--rterm-cursor-foreground", "#0b0f14");
      }

      this.drawRect(x, y, width, height, background);
      if (!cell.char || cell.char === " " || attrs.invisible) return;

      const glyph = this.glyph(cell.char, metrics, attrs, style);
      this.drawGlyph(x, y, width, height, attrs.dim ? dimColor(foreground) : foreground, glyph);
      this.drawDecorations(x, y, width, height, foreground, attrs, cell.link);
    }

    drawDecorations(x, y, width, height, foreground, attrs, link) {
      if (attrs.underline || link) this.drawRect(x, y + height - 2, width, 1, foreground);
      if (attrs.strikethrough) this.drawRect(x, y + Math.floor(height * 0.55), width, 1, foreground);
      if (attrs.overline) this.drawRect(x, y + 1, width, 1, foreground);
    }

    drawRect(x, y, width, height, color) {
      this.drawQuad(x, y, width, height, this.whiteTexture, [0, 0, 1, 1], color);
    }

    drawGlyph(x, y, width, height, color, glyph) {
      this.drawQuad(x, y, width, height, this.atlas.texture, glyph.uv, color);
    }

    drawQuad(x, y, width, height, texture, uv, colorValue) {
      const gl = this.gl;
      const x2 = x + width;
      const y2 = y + height;
      const [u1, v1, u2, v2] = uv;
      const data = new Float32Array([
        x, y, u1, v1,
        x2, y, u2, v1,
        x, y2, u1, v2,
        x, y2, u1, v2,
        x2, y, u2, v1,
        x2, y2, u2, v2
      ]);

      gl.useProgram(this.program);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER, data, gl.STREAM_DRAW);
      gl.enableVertexAttribArray(this.position);
      gl.vertexAttribPointer(this.position, 2, gl.FLOAT, false, 16, 0);
      gl.enableVertexAttribArray(this.texcoord);
      gl.vertexAttribPointer(this.texcoord, 2, gl.FLOAT, false, 16, 8);
      gl.uniform2f(this.resolution, this.logicalWidth, this.logicalHeight);
      const color = parseColor(colorValue, [229, 231, 235, 255]);
      gl.uniform4f(this.color, color[0] / 255, color[1] / 255, color[2] / 255, color[3] / 255);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.uniform1i(this.texture, 0);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    }

    glyph(char, metrics, attrs, style) {
      const key = [char, Math.ceil(metrics.width), Math.ceil(metrics.height), attrs.bold ? 1 : 0, attrs.italic ? 1 : 0].join(":");
      if (this.glyphs.has(key)) return this.glyphs.get(key);

      if (this.atlas.nextX + this.atlas.cellWidth > this.atlas.size) this.nextAtlasRow();
      if (this.atlas.nextY + this.atlas.cellHeight > this.atlas.size) this.createAtlas();

      const glyph = this.paintGlyph(char, metrics, attrs, style);
      this.glyphs.set(key, glyph);
      return glyph;
    }

    paintGlyph(char, metrics, attrs, style) {
      const atlas = this.atlas;
      const ctx = atlas.context;
      const x = atlas.nextX;
      const y = atlas.nextY;
      ctx.clearRect(x, y, atlas.cellWidth, atlas.cellHeight);
      ctx.fillStyle = "white";
      ctx.font = `${attrs.italic ? "italic " : ""}${attrs.bold ? "700 " : ""}${Math.max(1, Math.floor(metrics.height * 0.78))}px ${style.fontFamily || "monospace"}`;
      ctx.textBaseline = "alphabetic";
      ctx.fillText(char, x, y + Math.floor(metrics.height * 0.82));
      this.uploadAtlas();

      atlas.nextX += atlas.cellWidth;
      return {
        uv: [
          x / atlas.size,
          y / atlas.size,
          (x + atlas.cellWidth) / atlas.size,
          (y + atlas.cellHeight) / atlas.size
        ]
      };
    }

    nextAtlasRow() {
      this.atlas.nextX = 0;
      this.atlas.nextY += this.atlas.cellHeight;
    }

    createAtlas() {
      const canvas = document.createElement("canvas");
      canvas.width = 1024;
      canvas.height = 1024;
      this.atlas = {
        canvas,
        context: canvas.getContext("2d", { alpha: true }),
        texture: this.createTexture(),
        size: 1024,
        cellWidth: 64,
        cellHeight: 64,
        nextX: 0,
        nextY: 0
      };
      this.glyphs.clear();
      this.uploadAtlas();
    }

    uploadAtlas() {
      const gl = this.gl;
      gl.bindTexture(gl.TEXTURE_2D, this.atlas.texture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, this.atlas.canvas);
    }

    createSolidTexture() {
      const texture = this.createTexture();
      this.gl.bindTexture(this.gl.TEXTURE_2D, texture);
      this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA, 1, 1, 0, this.gl.RGBA, this.gl.UNSIGNED_BYTE, new Uint8Array([255, 255, 255, 255]));
      return texture;
    }

    createRasterTexture(frame, width, height) {
      const texture = this.createTexture();
      const pixels = new Uint8Array(width * height * 4);
      let offset = 0;
      for (let y = 0; y < height; y += 1) {
        const row = frame.pixels[y] || [];
        for (let x = 0; x < width; x += 1) {
          const pixel = row[x] || [0, 0, 0, 255];
          pixels[offset] = pixel[0] || 0;
          pixels[offset + 1] = pixel[1] || 0;
          pixels[offset + 2] = pixel[2] || 0;
          pixels[offset + 3] = pixel[3] == null ? 255 : pixel[3];
          offset += 4;
        }
      }
      this.gl.bindTexture(this.gl.TEXTURE_2D, texture);
      this.gl.pixelStorei(this.gl.UNPACK_ALIGNMENT, 1);
      this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA, width, height, 0, this.gl.RGBA, this.gl.UNSIGNED_BYTE, pixels);
      return texture;
    }

    createTexture() {
      const gl = this.gl;
      const texture = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      return texture;
    }

    createProgram() {
      const vertex = this.compile(this.gl.VERTEX_SHADER, `
        attribute vec2 a_position;
        attribute vec2 a_texcoord;
        uniform vec2 u_resolution;
        varying vec2 v_texcoord;
        void main() {
          vec2 zeroToOne = a_position / u_resolution;
          vec2 clip = zeroToOne * 2.0 - 1.0;
          gl_Position = vec4(clip * vec2(1.0, -1.0), 0.0, 1.0);
          v_texcoord = a_texcoord;
        }
      `);
      const fragment = this.compile(this.gl.FRAGMENT_SHADER, `
        precision mediump float;
        uniform sampler2D u_texture;
        uniform vec4 u_color;
        varying vec2 v_texcoord;
        void main() {
          vec4 sample = texture2D(u_texture, v_texcoord);
          gl_FragColor = vec4(sample.rgb * u_color.rgb, u_color.a * sample.a);
        }
      `);
      const program = this.gl.createProgram();
      this.gl.attachShader(program, vertex);
      this.gl.attachShader(program, fragment);
      this.gl.linkProgram(program);
      if (!this.gl.getProgramParameter(program, this.gl.LINK_STATUS)) {
        throw new Error(this.gl.getProgramInfoLog(program));
      }
      return program;
    }

    compile(type, source) {
      const shader = this.gl.createShader(type);
      this.gl.shaderSource(shader, source);
      this.gl.compileShader(shader);
      if (!this.gl.getShaderParameter(shader, this.gl.COMPILE_STATUS)) {
        throw new Error(this.gl.getShaderInfoLog(shader));
      }
      return shader;
    }

    bindContextEvents() {
      this.canvas.addEventListener("webglcontextlost", (event) => {
        event.preventDefault();
        this.ready = false;
        if (this.options.onContextLoss) this.options.onContextLoss(event);
      });
      this.canvas.addEventListener("webglcontextrestored", (event) => {
        this.gl = this.canvas.getContext("webgl2", { alpha: false }) || this.canvas.getContext("webgl", { alpha: false });
        this.ready = !!this.gl;
        if (this.ready) {
          this.program = this.createProgram();
          this.buffer = this.gl.createBuffer();
          this.whiteTexture = this.createSolidTexture();
          this.createAtlas();
          this.gl.enable(this.gl.BLEND);
          this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);
        }
        if (this.options.onContextRestore) this.options.onContextRestore(event);
      });
    }
  }

  function parseColor(value, fallback) {
    if (!value) return fallback;
    if (Array.isArray(value)) return value;
    const text = String(value).trim();
    const hex = text.match(/^#([0-9a-f]{6})$/i);
    if (hex) {
      const raw = hex[1];
      return [parseInt(raw.slice(0, 2), 16), parseInt(raw.slice(2, 4), 16), parseInt(raw.slice(4, 6), 16), 255];
    }
    const rgb = text.match(/^rgba?\(([^)]+)\)$/i);
    if (rgb) {
      const parts = rgb[1].split(",").map((part) => Number(part.trim()));
      return [parts[0] || 0, parts[1] || 0, parts[2] || 0, parts[3] == null ? 255 : Math.round(parts[3] * 255)];
    }
    return fallback;
  }

  function dimColor(value) {
    const color = parseColor(value, [229, 231, 235, 255]);
    return [Math.round(color[0] * 0.65), Math.round(color[1] * 0.65), Math.round(color[2] * 0.65), color[3]];
  }

  function styleValue(style, name, fallback) {
    if (!style || !style.getPropertyValue) return fallback;

    return style.getPropertyValue(name).trim() || fallback;
  }

  function isCursorCell(cell, row, cursor) {
    if (!cursor) return false;

    return Number(cursor.row || 0) === row && Number(cursor.col || 0) === Number(cell.col || 0);
  }

  function isSelectedCell(cell, row, selection) {
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

  global.RTermWebGLRenderer = RTermWebGLRenderer;
})(typeof window !== "undefined" ? window : globalThis);
