# frozen_string_literal: true

RSpec.describe RTerm::Common::UnicodeTableBuilder do
  let(:east_asian_width) do
    <<~DATA
      0041; Na # LATIN CAPITAL LETTER A
      00A1; A # INVERTED EXCLAMATION MARK
      1100..115F; W # Hangul Jamo
      FF01..FF60; F # Fullwidth ASCII variants
    DATA
  end

  let(:emoji_data) do
    <<~DATA
      1F1E6..1F1FF ; Regional_Indicator # flags
      1F300..1F64F ; Emoji_Presentation # emoji
      1F3FB..1F3FF ; Emoji_Modifier # skin tones
      1F3F4 ; Extended_Pictographic # black flag
    DATA
  end

  let(:variation_sequences) do
    <<~DATA
      2600 FE0E; text style;  # sun
      2600 FE0F; emoji style; # sun
    DATA
  end

  it "builds a provider from Unicode data file contents" do
    provider = described_class.from_strings(
      east_asian_width: east_asian_width,
      emoji_data: emoji_data,
      emoji_variation_sequences: variation_sequences,
      ambiguous_width: 2
    )

    expect(provider.char_width("A".ord)).to eq(1)
    expect(provider.char_width(0x00A1)).to eq(2)
    expect(provider.char_width(0x1100)).to eq(2)
    expect(provider.char_width(0x0301)).to eq(0)
    expect(provider.char_width(0x1F600)).to eq(2)
  end

  it "handles emoji variation, regional indicator, modifier, and tag sequences" do
    provider = described_class.from_strings(
      east_asian_width: east_asian_width,
      emoji_data: emoji_data,
      emoji_variation_sequences: variation_sequences
    )
    tag_sequence = [0x1F3F4, 0xE0067, 0xE0062, 0xE007F].pack("U*")

    expect(provider.grapheme_width("☀\uFE0E")).to eq(1)
    expect(provider.grapheme_width("☀\uFE0F")).to eq(2)
    expect(provider.grapheme_width("🇺🇸")).to eq(2)
    expect(provider.grapheme_width("👍🏻")).to eq(2)
    expect(provider.grapheme_width(tag_sequence)).to eq(2)
  end

  it "can be registered as a UnicodeHandler provider" do
    handler = RTerm::Common::UnicodeHandler.new
    provider = described_class.from_strings(
      east_asian_width: east_asian_width,
      emoji_data: emoji_data,
      emoji_variation_sequences: variation_sequences
    )

    handler.register("fixture", provider)
    handler.active_version = "fixture"

    expect(handler.char_width("☀\uFE0E")).to eq(1)
    expect(handler.char_width("☀\uFE0F")).to eq(2)
  end
end
