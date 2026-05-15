const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

class FakeClassList {
  constructor(element) {
    this.element = element;
    this.values = new Set();
  }

  add(...names) {
    names.forEach((name) => this.values.add(name));
    this.element.className = Array.from(this.values).join(" ");
  }

  remove(...names) {
    names.forEach((name) => this.values.delete(name));
    this.element.className = Array.from(this.values).join(" ");
  }

  contains(name) {
    return this.values.has(name);
  }
}

class FakeElement {
  constructor(tagName = "div") {
    this.tagName = tagName.toUpperCase();
    this.children = [];
    this.parentElement = null;
    this.parentNode = null;
    this.dataset = {};
    this.style = {};
    this.attributes = {};
    this._className = "";
    this.classList = new FakeClassList(this);
    this.eventHandlers = {};
    this.tabIndex = -1;
    this.textContent = "";
    this.width = 0;
    this.height = 0;
    this.lastImageData = null;
  }

  set className(value) {
    this._className = String(value);
    if (this.classList) {
      this.classList.values = new Set(this._className.split(/\s+/).filter(Boolean));
    }
  }

  get className() {
    return this._className;
  }

  setAttribute(name, value) {
    this.attributes[name] = String(value);
  }

  appendChild(child) {
    child.parentElement = this;
    child.parentNode = this;
    this.children.push(child);
    return child;
  }

  replaceChildren(...children) {
    this.children = [];
    children.forEach((child) => this.appendChild(child));
  }

  addEventListener(name, handler) {
    this.eventHandlers[name] = handler;
  }

  focus() {
    this.focused = true;
  }

  blur() {
    this.focused = false;
  }

  getContext(type) {
    if (type !== "2d") return null;

    return {
      createImageData: (width, height) => ({
        width,
        height,
        data: new Uint8ClampedArray(width * height * 4)
      }),
      putImageData: (image) => {
        this.lastImageData = image;
      }
    };
  }

  getBoundingClientRect() {
    return { width: 720, height: 360, left: 0, top: 0 };
  }

  querySelectorAll(selector) {
    const matches = [];
    const className = selector.startsWith(".") ? selector.slice(1) : null;
    this.walk((element) => {
      if (!className) return;
      if (element.classList.contains(className)) matches.push(element);
    });
    return matches;
  }

  closest(selector) {
    const className = selector.startsWith(".") ? selector.slice(1) : null;
    let element = this;
    while (element) {
      if (className && element.classList.contains(className)) return element;
      element = element.parentElement;
    }
    return null;
  }

  contains(target) {
    let found = false;
    this.walk((element) => {
      if (element === target) found = true;
    });
    return found;
  }

  walk(callback) {
    callback(this);
    this.children.forEach((child) => child.walk(callback));
  }
}

class FakeDocument {
  constructor(root) {
    this.root = root;
    this.fonts = { add() {} };
  }

  querySelector() {
    return this.root;
  }

  createElement(tagName) {
    return new FakeElement(tagName);
  }

  createDocumentFragment() {
    return new FakeElement("fragment");
  }
}

if (typeof global.CustomEvent === "undefined") {
  global.CustomEvent = class CustomEvent extends Event {
    constructor(type, init = {}) {
      super(type);
      this.detail = init.detail;
    }
  };
}

const root = new FakeElement("div");
global.document = new FakeDocument(root);
global.navigator = {};
global.ResizeObserver = class ResizeObserver {
  observe() {}
  disconnect() {}
};

vm.runInThisContext(fs.readFileSync("lib/rterm/browser_adapter/browser_adapter.js", "utf8"));

const adapter = new global.RTermBrowserAdapter("#terminal", {
  renderer: "raster",
  raster: true,
  cols: 10,
  rows: 2
});
const payload = adapter.createSessionPayload();
assert.equal(payload.browserRenderer, "raster");
assert.equal(payload.raster, true);
assert.equal(adapter.getOption("renderer"), "raster");

adapter.applyCommand({
  type: "screen",
  payload: {
    screen: {
      cols: 10,
      rows_count: 1,
      cursor: { row: 0, col: 1 },
      rows: [
        {
          row: 0,
          cells: [
            { col: 0, char: "h", width: 1, colors: {}, attributes: {}, link: { uri: "https://example.com" } },
            { col: 1, char: "i", width: 1, colors: {}, attributes: { bold: true } }
          ]
        }
      ]
    }
  }
});

const cells = root.querySelectorAll(".rterm-browser-cell");
assert.equal(cells.length, 2);
assert.equal(cells[0].dataset.linkUri, "https://example.com");
assert.equal(cells[1].classList.contains("is-cursor"), true);

let hostEvent = null;
adapter.sendHostEvent = (event) => {
  hostEvent = event;
  return event;
};
adapter.sendLinkEvent("link_activate", cells[0]);
assert.deepEqual(hostEvent, {
  type: "link_activate",
  uri: "https://example.com",
  row: 0,
  col: 0
});

adapter.applyCommand({
  type: "selection_change",
  payload: {
    selection: { type: "linear" },
    start: { x: 0, y: 0 },
    end: { x: 1, y: 0 }
  }
});
assert.equal(cells[0].classList.contains("is-selected"), true);

adapter.applyCommand({
  type: "raster",
  payload: {
    frame: {
      width: 1,
      height: 1,
      pixels: [[[12, 34, 56, 255]]]
    }
  }
});
assert.equal(adapter.canvas.lastImageData.data[0], 12);
assert.equal(adapter.canvas.lastImageData.data[1], 34);
assert.equal(adapter.canvas.lastImageData.data[2], 56);
assert.deepEqual(adapter.fit().cell, adapter.cell);
adapter.refresh().setOption("rows", 3).focus().blur();
assert.equal(adapter.rows, 3);

console.log("browser-adapter-smoke-ok");
