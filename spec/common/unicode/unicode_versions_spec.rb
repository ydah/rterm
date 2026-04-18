# frozen_string_literal: true

RSpec.describe RTerm::Common::UnicodeV6 do
  it "acts as a unicode width provider" do
    provider = described_class.new

    expect(provider.char_width("A".ord)).to eq(1)
    expect(provider.char_width("一".ord)).to eq(2)
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
end
