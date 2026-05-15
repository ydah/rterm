# frozen_string_literal: true

RSpec.describe RTerm::Addon::HtmlRenderer do
  it "renders terminal rows as escaped HTML with ARIA metadata" do
    terminal = RTerm::Terminal.new(cols: 5, rows: 1)
    renderer = described_class.new(className: "terminal")

    terminal.load_addon(renderer)
    terminal.write("<&>")

    html = renderer.toHtml(styles: false)
    expect(html).to include('class="terminal"')
    expect(html).to include('role="application"')
    expect(html).to include('role="row"')
    expect(html).to include('role="gridcell"')
    expect(html).to include("&lt;")
    expect(html).to include("&amp;")
    expect(html).to include("&gt;")
    expect(html).to include('data-cursor-col="3"')
  end

  it "can render a standalone HTML document and accessibility grid" do
    terminal = RTerm::Terminal.new(cols: 2, rows: 1, screen_reader_mode: true)
    renderer = described_class.new

    terminal.open
    terminal.load_addon(renderer)
    terminal.write("ok")

    expect(renderer.html(document: true)).to start_with("<!doctype html>")
    expect(renderer.html).to include("rterm-live-region")
    expect(renderer.ariaHtml).to include('role="grid"')
    expect(renderer.ariaHtml).to include('aria-rowcount="1"')
    expect(renderer.ariaHtml).to include("ok")
    expect(renderer.css).to include(".rterm-html")
  end
end
