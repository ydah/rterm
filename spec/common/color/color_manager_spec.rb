# frozen_string_literal: true

RSpec.describe RTerm::Common::ColorPalette do
  it "returns ANSI colors from the active theme" do
    palette = described_class.new(RTerm::Theme.new(red: "#ff0000"))

    expect(palette[1]).to eq("#ff0000")
    expect(palette[15]).to eq("#ffffff")
  end

  it "builds xterm 256-color entries" do
    palette = described_class.new

    expect(palette[16]).to eq("#000000")
    expect(palette[231]).to eq("#ffffff")
    expect(palette[232]).to eq("#080808")
  end
end

RSpec.describe RTerm::Common::ColorManager do
  it "updates palette colors and resets them" do
    manager = described_class.new

    manager.set_ansi_color(1, "#ff1111")
    expect(manager.palette[1]).to eq("#ff1111")

    manager.reset_ansi_color(1)
    expect(manager.palette[1]).to eq(RTerm::Theme.new.red)
  end

  it "tracks default foreground, background, and cursor colors" do
    manager = described_class.new

    manager.foreground = "#eeeeee"
    manager.background = "#111111"
    manager.cursor = "#00ff00"

    expect(manager.foreground).to eq("#eeeeee")
    expect(manager.background).to eq("#111111")
    expect(manager.cursor).to eq("#00ff00")
  end
end
