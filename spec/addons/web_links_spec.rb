# frozen_string_literal: true

RSpec.describe RTerm::Addon::WebLinks do
  let(:terminal) { RTerm::Terminal.new(cols: 40, rows: 4) }
  let(:addon) { described_class.new }

  before do
    terminal.load_addon(addon)
  end

  it "finds URLs on a visible row" do
    terminal.write("open https://example.com now")

    link = addon.find_links.first

    expect(link).to include(url: "https://example.com", row: 0, col: 5, length: 19)
    expect(link[:ranges]).to eq([{ row: 0, col: 5, length: 19 }])
  end

  it "finds URLs across wrapped rows" do
    wrapped = RTerm::Terminal.new(cols: 12, rows: 3)
    wrapped_addon = described_class.new
    wrapped.load_addon(wrapped_addon)
    wrapped.write("https://example.com")

    link = wrapped_addon.find_links.first

    expect(link).to include(url: "https://example.com", row: 0, col: 0, length: 19)
    expect(link[:ranges]).to eq([{ row: 0, col: 0, length: 12 }, { row: 1, col: 0, length: 7 }])
    expect(wrapped_addon.link_at(1, 2)[:url]).to eq("https://example.com")
  end

  it "trims trailing sentence punctuation from detected URLs" do
    terminal.write("(https://example.com).")

    link = addon.find_links.first

    expect(link).to include(url: "https://example.com", row: 0, col: 1, length: 19)
  end

  it "supports custom link providers and open callbacks" do
    activated = nil
    opened = nil
    disposable = addon.register_link_provider do |text, _row|
      start = text.index("printf")
      [{ url: "man://printf", start: start, length: 6, activate: ->(link) { activated = link[:url] } }]
    end
    addon.on_link { |link| opened = link[:url] }
    terminal.write("run printf")

    link = addon.find_links.first
    result = addon.open_link(link)
    disposable.dispose

    expect(link).to include(url: "man://printf", row: 0, col: 4, length: 6)
    expect(result).to be true
    expect(activated).to eq("man://printf")
    expect(opened).to eq("man://printf")
    expect(addon.find_links).to be_empty
  end

  it "provides row-scoped links through provider-style API" do
    terminal.write("https://example.com\r\nhttps://example.org")
    yielded = nil

    links = addon.provide_links(1) { |items| yielded = items }

    expect(links.map { |link| link[:url] }).to eq(["https://example.org"])
    expect(yielded).to eq(links)
  end
end
