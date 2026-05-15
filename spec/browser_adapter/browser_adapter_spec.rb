# frozen_string_literal: true

require "json"

RSpec.describe RTerm::BrowserAdapter do
  it "exposes bundled browser assets" do
    js = described_class.javascript
    css = described_class.stylesheet

    expect(js).to include("RTermBrowserAdapter")
    expect(js).to include("RTermWebGLRenderer")
    expect(js).to include("host_event")
    expect(js).to include("ResizeObserver")
    expect(js).to include("navigator.clipboard")
    expect(js).to include("FontFace")
    expect(js).to include("selection_change")
    expect(js).to include("context_menu")
    expect(js).to include("linkactivate")
    expect(js).to include("link_hover")
    expect(js).to include("browserRenderer")
    expect(js).to include("createSessionPayload")
    expect(js).to include("\"raster\"")
    expect(js).to include("renderRasterToCanvas")
    expect(js).to include("createImageData")
    expect(js).to include("setOption")
    expect(js).to include("renderAccessibilityNode")
    expect(js).to include("renderRaster")
    expect(js).to include("createProgram")
    expect(js).to include("texture2D")
    expect(css).to include(".rterm-browser")
    expect(css).to include(".rterm-browser-webgl")
    expect(css).to include(".rterm-browser.is-canvas")
    expect(css).to include(".rterm-browser-accessibility")
    expect(css).to include(".rterm-browser-cell.is-selected")
    expect(css).to include(".rterm-browser-cell.is-cursor")
  end

  it "returns concrete asset paths and rejects unknown assets" do
    path = described_class.asset_path("browser_adapter.js")
    renderer_path = described_class.asset_path("webgl_renderer.js")
    module_path = described_class.asset_path("index.mjs")
    types_path = described_class.asset_path("index.d.ts")

    expect(File.file?(path)).to be true
    expect(File.file?(renderer_path)).to be true
    expect(File.file?(module_path)).to be true
    expect(File.file?(types_path)).to be true
    expect { described_class.asset_path("../rterm.rb") }
      .to raise_error(ArgumentError, /unknown browser adapter asset/)
  end

  it "builds inline tags for simple Rack responses" do
    expect(described_class.script_tag).to start_with("<script>")
    expect(described_class.style_tag).to start_with("<style>")
  end

  it "exposes an ES module entry and TypeScript declarations" do
    package = JSON.parse(File.read(File.expand_path("../../package.json", __dir__)))
    declarations = File.read(described_class.asset_path("index.d.ts"))

    expect(package["module"]).to eq("./lib/rterm/browser_adapter/index.mjs")
    expect(package["types"]).to eq("./lib/rterm/browser_adapter/index.d.ts")
    expect(package["exports"]["."]["import"]).to eq("./lib/rterm/browser_adapter/index.mjs")
    expect(declarations).to include("class RTermBrowserAdapter")
    expect(declarations).to include("class RTermWebGLRenderer")
  end
end
