# frozen_string_literal: true

RSpec.describe RTerm::Addon::RasterRenderer do
  it "renders terminal cells into an RGBA frame" do
    terminal = RTerm::Terminal.new(cols: 2, rows: 1)
    renderer = described_class.new(cell_width: 4, cell_height: 4, draw_cursor: false)
    frames = []

    renderer.onRaster { |payload| frames << payload }
    terminal.load_addon(renderer)
    terminal.write("\e[31mA")

    expect(renderer.frame).to include(width: 8, height: 4, cell_width: 4, cell_height: 4)
    expect(renderer.pixelAt(0, 0)).to eq([0, 0, 0, 255])
    expect(renderer.pixelAt(1, 1)).to eq([205, 49, 49, 255])
    expect(renderer.toPpm.lines.first.strip).to eq("P3")
    expect(frames.last).to include(type: :raster)
  end

  it "renders cursor blink state" do
    terminal = RTerm::Terminal.new(cols: 2, rows: 1, cursor_blink: true)
    renderer = described_class.new(cell_width: 2, cell_height: 2, cursor_blink_interval: 0.1)

    terminal.load_addon(renderer)

    expect(renderer.frame[:cursor]).to include(row: 0, col: 0, visible: true)
    expect(renderer.advanceCursorBlink(now: Time.at(0))).to be true
    expect(renderer.advanceCursorBlink(now: Time.at(0.2))).to be false
    expect(renderer.frame[:cursor]).to be_nil
  end

  it "composes decoded sixel images into the raster frame" do
    terminal = RTerm::Terminal.new(cols: 2, rows: 1)
    renderer = described_class.new(cell_width: 2, cell_height: 2, draw_cursor: false)

    terminal.load_addon(renderer)
    terminal.write("\ePq\"1;1;2;2#2;2;100;0;0A\e\\")

    expect(renderer.frame[:images].last).to include(protocol: :sixel, x: 0, y: 0, width: 2, height: 2)
    expect(renderer.pixelAt(0, 1)).to eq([255, 0, 0, 255])
  end

  it "composes iTerm2 image previews into the raster frame" do
    terminal = RTerm::Terminal.new(cols: 3, rows: 2)
    renderer = described_class.new(cell_width: 4, cell_height: 4, draw_cursor: false)

    terminal.load_addon(renderer)
    terminal.write("\e]1337;File=name=test.png;inline=1;width=2;height=1:#{["PNG"].pack("m0")}\a")

    expect(renderer.frame[:images].last).to include(
      protocol: :iterm2,
      format: :binary,
      name: "test.png",
      byte_size: 3,
      x: 0,
      y: 0,
      width: 8,
      height: 4
    )
    expect(renderer.pixelAt(1, 1)).not_to eq([0, 0, 0, 255])
  end
end
