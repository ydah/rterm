const assert = require("assert");
const fs = require("fs");

let chromium;
try {
  ({ chromium } = require("playwright"));
} catch (_error) {
  console.log("browser-adapter-playwright-missing");
  process.exit(0);
}

const escapeScript = (source) => source.replace(/<\/script/gi, "<\\/script");

(async () => {
  let browser;
  try {
    browser = await chromium.launch();
  } catch (error) {
    console.log(`browser-adapter-playwright-unavailable ${String(error.message).split("\n")[0]}`);
    process.exit(0);
  }

  try {
    const page = await browser.newPage();
    const browserAdapter = fs.readFileSync("lib/rterm/browser_adapter/browser_adapter.js", "utf8");
    await page.setContent(`
      <!doctype html>
      <meta charset="utf-8">
      <div id="terminal" style="width: 320px; height: 180px"></div>
      <script>${escapeScript(browserAdapter)}</script>
    `);

    const result = await page.evaluate(() => {
      window.hostEvents = [];
      const adapter = new window.RTermBrowserAdapter("#terminal", {
        renderer: "raster",
        raster: true,
        cols: 4,
        rows: 2
      });
      adapter.sendHostEvent = (event) => {
        window.hostEvents.push(event);
        return event;
      };
      adapter.applyCommand({
        type: "screen",
        payload: {
          screen: {
            cols: 4,
            rows_count: 2,
            cursor: { row: 0, col: 1 },
            rows: [
              {
                row: 0,
                cells: [
                  { col: 0, char: "u", width: 1, colors: {}, attributes: {}, link: { uri: "https://example.com" } },
                  { col: 1, char: "i", width: 1, colors: {}, attributes: { bold: true } }
                ]
              }
            ]
          }
        }
      });
      adapter.applyCommand({
        type: "selection_change",
        payload: {
          selection: { type: "linear" },
          start: { x: 0, y: 0 },
          end: { x: 1, y: 0 }
        }
      });

      const link = document.querySelector(".rterm-browser-cell.is-link");
      link.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, button: 0, cancelable: true }));
      link.dispatchEvent(new MouseEvent("mouseout", { bubbles: true, relatedTarget: document.body }));
      adapter.applyCommand({
        type: "raster",
        payload: {
          frame: {
            width: 1,
            height: 1,
            pixels: [[[90, 40, 10, 255]]]
          }
        }
      });

      return {
        hostEvents: window.hostEvents,
        linkText: link.textContent,
        selected: link.classList.contains("is-selected"),
        canvas: Array.from(adapter.canvas.getContext("2d").getImageData(0, 0, 1, 1).data),
        renderedClass: adapter.element.classList.contains("is-canvas")
      };
    });

    assert.equal(result.linkText, "u");
    assert.equal(result.selected, true);
    assert.equal(result.renderedClass, true);
    assert.deepEqual(result.canvas, [90, 40, 10, 255]);
    assert.deepEqual(
      result.hostEvents.map((event) => event.type),
      ["link_hover", "link_activate", "link_leave"]
    );
    console.log("browser-adapter-playwright-ok");
  } finally {
    await browser.close();
  }
})();
