# frozen_string_literal: true

require "zlib"

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
    expect(renderer.pixelAt(2, 1)).to eq([205, 49, 49, 255])
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

  it "composes iTerm2 PNG pixels into the raster frame" do
    terminal = RTerm::Terminal.new(cols: 3, rows: 2)
    renderer = described_class.new(cell_width: 4, cell_height: 4, draw_cursor: false)

    terminal.load_addon(renderer)
    terminal.write("\e]1337;File=name=test.png;inline=1;width=2;height=1:#{[png_bytes].pack("m0")}\a")

    expect(renderer.frame[:images].last).to include(
      protocol: :iterm2,
      format: :rgba,
      media_type: :png,
      name: "test.png",
      x: 0,
      y: 0,
      width: 8,
      height: 4
    )
    expect(renderer.pixelAt(1, 1)).to eq([255, 0, 0, 255])
    expect(renderer.pixelAt(5, 1)).to eq([0, 255, 0, 255])
  end

  it "previews iTerm2 binary payloads when pixels cannot be decoded" do
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

  it "renders bitmap glyph masks for terminal text" do
    terminal = RTerm::Terminal.new(cols: 1, rows: 1)
    renderer = described_class.new(cell_width: 6, cell_height: 8, draw_cursor: false)

    terminal.load_addon(renderer)
    terminal.write("A")

    expect(renderer.pixelAt(2, 1)).to eq([255, 255, 255, 255])
    expect(renderer.pixelAt(1, 1)).to eq([0, 0, 0, 255])
  end

  it "composes iTerm2 GIF pixels into the raster frame" do
    terminal = RTerm::Terminal.new(cols: 1, rows: 1)
    renderer = described_class.new(cell_width: 4, cell_height: 4, draw_cursor: false)

    terminal.load_addon(renderer)
    terminal.write("\e]1337;File=name=test.gif;inline=1;width=1;height=1:#{[gif_bytes].pack("m0")}\a")

    expect(renderer.frame[:images].last).to include(protocol: :iterm2, format: :rgba, media_type: :gif)
    expect(renderer.pixelAt(1, 1)).to eq([255, 0, 0, 255])
  end

  it "composes iTerm2 JPEG structural previews into the raster frame" do
    terminal = RTerm::Terminal.new(cols: 2, rows: 1)
    renderer = described_class.new(cell_width: 4, cell_height: 4, draw_cursor: false)

    terminal.load_addon(renderer)
    terminal.write("\e]1337;File=name=test.jpg;inline=1;width=2;height=1:#{[jpeg_bytes].pack("m0")}\a")

    expect(renderer.frame[:images].last).to include(protocol: :iterm2, format: :sampled, media_type: :jpeg)
    expect(renderer.pixelAt(1, 1)).not_to eq([0, 0, 0, 255])
  end

  def png_bytes
    header = [2, 1, 8, 6, 0, 0, 0].pack("NNCCCCC")
    row = [0, 255, 0, 0, 255, 0, 255, 0, 255].pack("C*")
    RTerm::Common::PngDecoder::SIGNATURE +
      png_chunk("IHDR", header) +
      png_chunk("IDAT", Zlib::Deflate.deflate(row)) +
      png_chunk("IEND", "")
  end

  def png_chunk(type, data)
    body = type + data
    [data.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
  end

  def gif_bytes
    [
      "GIF89a",
      [1, 1, 0x80, 0, 0].pack("vvCCC"),
      [255, 0, 0, 0, 0, 0].pack("C*"),
      ",",
      [0, 0, 1, 1, 0].pack("vvvvC"),
      [2, 2, 0x44, 0x01, 0].pack("C*"),
      ";"
    ].join
  end

  def jpeg_bytes
    frame = [8, 1, 2, 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1].pack("CnnC9")
    "\xff\xd8".b + "\xff\xc0".b + [frame.bytesize + 2].pack("n") + frame + "\xff\xd9".b
  end
end
