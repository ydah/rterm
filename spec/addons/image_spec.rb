# frozen_string_literal: true

RSpec.describe RTerm::Addon::Image do
  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }
  let(:addon) { described_class.new }

  before do
    terminal.load_addon(addon)
  end

  it "tracks image payload events" do
    seen = []
    addon.on_image { |payload| seen << payload }

    terminal.write("\ePqABCDEF\e\\")

    expect(seen.first).to include(protocol: :sixel, data: "ABCDEF")
    expect(addon.images).to include(seen.first)
    expect(addon.count).to eq(1)
    expect(addon.empty?).to be(false)
  end

  it "filters images by protocol" do
    terminal.write("\ePqABCDEF\e\\")
    terminal.write("\e]1337;File=name=test.png;inline=1:AAAA\a")

    expect(addon.protocols).to contain_exactly(:sixel, :iterm2)
    expect(addon.by_protocol(:sixel).length).to eq(1)
    expect(addon.byProtocol("iterm2").first).to include(protocol: :iterm2)
  end

  it "finds images by occupied cell" do
    terminal.write("\e]1337;File=name=test.png;inline=1;width=3;height=2:AAAA\a")

    image = addon.at(1, 2)

    expect(image).to include(protocol: :iterm2)
    expect(addon.at(3, 2)).to be_nil
  end

  it "clears images by protocol or buffer" do
    cleared = []
    addon.on_clear { |items| cleared << items }
    terminal.write("\ePqABCDEF\e\\")
    terminal.write("\e]1337;File=name=test.png;inline=1:AAAA\a")

    removed = addon.clear(protocol: :sixel)

    expect(removed.map { |image| image[:protocol] }).to eq([:sixel])
    expect(addon.images.map { |image| image[:protocol] }).to eq([:iterm2])
    expect(cleared.first).to eq(removed)

    addon.clear(buffer: :normal)
    expect(addon.images).to be_empty
  end

  it "stops forwarding events after disposal" do
    seen = []
    addon.onImage { |payload| seen << payload }
    addon.dispose

    terminal.write("\ePqABCDEF\e\\")

    expect(seen).to be_empty
  end
end
