# frozen_string_literal: true

RSpec.describe RTerm::Common::UnicodeV6 do
  it "acts as a unicode width provider" do
    provider = described_class.new

    expect(provider.char_width("A".ord)).to eq(1)
    expect(provider.char_width("一".ord)).to eq(2)
    expect(provider.char_width(0x1FAE0)).to eq(1)
  end
end

RSpec.describe RTerm::Common::UnicodeV15 do
  it "uses Unicode 15 emoji ranges by default" do
    provider = described_class.new

    expect(provider.char_width(0x1FAE0)).to eq(2)
  end
end

RSpec.describe RTerm::Common::UnicodeHandler do
  it "provides specification aliases and helpers" do
    handler = described_class.new

    expect(handler.is_wide("一".ord)).to be true
    expect(handler.wide?("A".ord)).to be false
    expect(handler.is_emoji("😀".ord)).to be true
  end

  it "splits grapheme clusters without separating combining marks" do
    handler = described_class.new

    expect(handler.grapheme_clusters("e\u0301x")).to eq(["e\u0301", "x"])
  end

  it "registers bundled unicode version providers" do
    handler = described_class.new

    expect(handler.versions).to include("6", "11", "15")
    handler.active_version = "15"
    expect(handler.char_width("語".ord)).to eq(2)
  end

  it "uses version-specific emoji ranges" do
    handler = described_class.new

    handler.active_version = "6"
    expect(handler.char_width(0x1FAE0)).to eq(1)

    handler.active_version = "15"
    expect(handler.char_width(0x1FAE0)).to eq(2)
  end

  it "measures emoji variation sequences as wide grapheme clusters" do
    handler = described_class.new

    expect(handler.char_width("©")).to eq(1)
    expect(handler.char_width("©\uFE0F")).to eq(2)
    expect(handler.char_width("☀\uFE0E")).to eq(1)
    expect(handler.char_width("☀\uFE0F")).to eq(2)
    expect(handler.string_width("a©\uFE0Fb")).to eq(4)
  end

  it "measures emoji grapheme edge cases as single wide cells" do
    handler = described_class.new
    tag_sequence = [0x1F3F4, 0xE0067, 0xE0062, 0xE007F].pack("U*")

    expect(handler.char_width("👨‍👩‍👧‍👦")).to eq(2)
    expect(handler.char_width("🇺🇸")).to eq(2)
    expect(handler.char_width("👍🏻")).to eq(2)
    expect(handler.char_width(tag_sequence)).to eq(2)
  end

  it "keeps combining grapheme clusters at the base character width" do
    handler = described_class.new

    expect(handler.char_width("e\u0301")).to eq(1)
    expect(handler.string_width("e\u0301x")).to eq(2)
  end
end
