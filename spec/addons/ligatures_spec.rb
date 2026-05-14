# frozen_string_literal: true

RSpec.describe RTerm::Addon::Ligatures do
  let(:terminal) { RTerm::Terminal.new(cols: 40, rows: 4) }
  let(:addon) { described_class.new(patterns: %w[=== == => ffi]) }

  before do
    terminal.load_addon(addon)
  end

  it "registers a character joiner when activated" do
    expect(addon.joiner_id).to be_a(Integer)
    expect(addon).to be_enabled
  end

  it "finds non-overlapping ligature ranges by longest pattern" do
    ranges = addon.ranges("a === b == c => ffi")

    expect(ranges).to eq(
      [
        { start: 2, end: 5, text: "===", row: nil },
        { start: 8, end: 10, text: "==", row: nil },
        { start: 13, end: 15, text: "=>", row: nil },
        { start: 16, end: 19, text: "ffi", row: nil }
      ]
    )
  end

  it "returns character joiner ranges" do
    expect(addon.character_joiner_ranges("a => b")).to eq([[2, 4]])
    expect(addon.characterJoinerRanges("ffi")).to eq([[0, 3]])
  end

  it "finds ranges for a buffer line" do
    terminal.write("a => b")

    expect(addon.line_ranges(0)).to eq([{ start: 2, end: 4, text: "=>", row: 0 }])
    expect(addon.lineRanges(1)).to be_empty
  end

  it "can add and remove patterns" do
    changes = []
    addon.on_change { |state| changes << state }

    expect(addon.register("=~")).to be(true)
    expect(addon.registerPattern("=~")).to be(false)
    expect(addon.ranges("a =~ b").first).to include(text: "=~")

    expect(addon.deregister("=~")).to be(true)
    expect(addon.deregisterPattern("=~")).to be(false)
    expect(addon.ranges("a =~ b")).to be_empty
    expect(changes).not_to be_empty
  end

  it "can be disabled and re-enabled" do
    addon.disable
    expect(addon.character_joiner_ranges("a => b")).to be_empty

    addon.enable
    expect(addon.character_joiner_ranges("a => b")).to eq([[2, 4]])
  end

  it "deregisters its character joiner on dispose" do
    id = addon.joiner_id

    addon.dispose

    expect(addon.joiner_id).to be_nil
    expect(terminal.deregister_character_joiner(id)).to be(false)
  end
end
