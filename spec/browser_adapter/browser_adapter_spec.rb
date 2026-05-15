# frozen_string_literal: true

RSpec.describe RTerm::BrowserAdapter do
  it "exposes bundled browser assets" do
    js = described_class.javascript
    css = described_class.stylesheet

    expect(js).to include("RTermBrowserAdapter")
    expect(js).to include("host_event")
    expect(js).to include("ResizeObserver")
    expect(js).to include("navigator.clipboard")
    expect(js).to include("FontFace")
    expect(css).to include(".rterm-browser")
  end

  it "returns concrete asset paths and rejects unknown assets" do
    path = described_class.asset_path("browser_adapter.js")

    expect(File.file?(path)).to be true
    expect { described_class.asset_path("../rterm.rb") }
      .to raise_error(ArgumentError, /unknown browser adapter asset/)
  end

  it "builds inline tags for simple Rack responses" do
    expect(described_class.script_tag).to start_with("<script>")
    expect(described_class.style_tag).to start_with("<style>")
  end
end
