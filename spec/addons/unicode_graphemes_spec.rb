# frozen_string_literal: true

RSpec.describe RTerm::Addon::UnicodeGraphemes do
  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }
  let(:addon) { described_class.new }

  it "registers and activates a grapheme provider" do
    terminal.unicode.active_version = "15"

    terminal.load_addon(addon)

    expect(addon).to be_active
    expect(addon.previous_version).to eq("15")
    expect(addon.provider.version).to eq("graphemes")
    expect(terminal.unicode.versions).to include("graphemes")
    expect(terminal.unicode.active_version).to eq("graphemes")
  end

  it "measures grapheme clusters through the active provider" do
    terminal.load_addon(addon)

    expect(terminal.internal.unicode_handler.char_width("e\u0301")).to eq(1)
    expect(terminal.internal.unicode_handler.char_width("👨‍👩‍👧‍👦")).to eq(2)
    expect(terminal.internal.unicode_handler.char_width("🇺🇸")).to eq(2)
    expect(addon.string_width("a©\uFE0Fb")).to eq(4)
  end

  it "exposes cluster helpers" do
    terminal.load_addon(addon)

    expect(addon.grapheme_clusters("e\u0301x")).to eq(["e\u0301", "x"])
    expect(addon.graphemeClusters("👍🏻!")).to eq(["👍🏻", "!"])
  end

  it "uses the configured base width version for codepoints" do
    custom = described_class.new(base_version: "6")
    terminal.load_addon(custom)

    expect(custom.provider.base_version).to eq("6")
    expect(terminal.internal.unicode_handler.char_width(0x1FAE0)).to eq(1)
    expect(terminal.internal.unicode_handler.char_width("👍🏻")).to eq(2)
  end

  it "restores the prior width version on dispose" do
    terminal.unicode.active_version = "11"
    terminal.load_addon(addon)

    addon.dispose

    expect(addon).not_to be_active
    expect(terminal.unicode.active_version).to eq("11")
  end
end
