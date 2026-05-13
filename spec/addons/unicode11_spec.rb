# frozen_string_literal: true

RSpec.describe RTerm::Addon::Unicode11 do
  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }
  let(:addon) { described_class.new }

  it "activates Unicode 11 widths" do
    terminal.unicode.active_version = "6"

    terminal.load_addon(addon)

    expect(addon.version).to eq("11")
    expect(addon.previous_version).to eq("6")
    expect(addon).to be_active
    expect(terminal.unicode.active_version).to eq("11")
  end

  it "restores the prior width version on dispose" do
    terminal.unicode.active_version = "15"
    terminal.load_addon(addon)

    addon.dispose

    expect(addon).not_to be_active
    expect(terminal.unicode.active_version).to eq("15")
  end

  it "affects rendered cell widths through the terminal handler" do
    terminal.unicode.active_version = "6"
    expect(terminal.internal.unicode_handler.char_width(0x1FAE0)).to eq(1)

    terminal.load_addon(addon)

    expect(terminal.internal.unicode_handler.char_width(0x1FAE0)).to eq(1)
    expect(terminal.internal.unicode_handler.char_width("語".ord)).to eq(2)
  end
end
