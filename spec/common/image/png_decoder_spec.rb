# frozen_string_literal: true

require "zlib"

RSpec.describe RTerm::Common::PngDecoder do
  it "decodes non-interlaced RGBA PNG pixels" do
    bytes = png_bytes(
      2,
      1,
      6,
      8,
      [[0, 255, 0, 0, 255, 0, 255, 0, 128].pack("C*")]
    )

    decoded = described_class.decode(bytes)

    expect(decoded).to include(format: :rgba, media_type: :png, width: 2, height: 1)
    expect(decoded[:pixels]).to eq([[[255, 0, 0, 255], [0, 255, 0, 128]]])
  end

  it "decodes palette PNG transparency" do
    bytes = png_bytes(
      2,
      1,
      3,
      1,
      [[0, 0b01000000].pack("C*")],
      palette: [255, 0, 0, 0, 0, 255].pack("C*"),
      transparency: [255, 64].pack("C*")
    )

    decoded = described_class.decode(bytes)

    expect(decoded[:pixels]).to eq([[[255, 0, 0, 255], [0, 0, 255, 64]]])
  end

  it "decodes Adam7 interlaced PNG pixels" do
    bytes = png_bytes(
      2,
      2,
      6,
      8,
      [
        [0, 255, 0, 0, 255].pack("C*"),
        [0, 0, 255, 0, 255].pack("C*"),
        [0, 0, 0, 255, 255, 255, 255, 255, 255].pack("C*")
      ],
      interlace: 1
    )

    decoded = described_class.decode(bytes)

    expect(decoded[:pixels]).to eq([
      [[255, 0, 0, 255], [0, 255, 0, 255]],
      [[0, 0, 255, 255], [255, 255, 255, 255]]
    ])
  end

  it "returns nil for unsupported bytes" do
    expect(described_class.decode("not-png")).to be_nil
  end

  def png_bytes(width, height, color_type, bit_depth, rows, palette: nil, transparency: nil, interlace: 0)
    header = [width, height, bit_depth, color_type, 0, 0, interlace].pack("NNCCCCC")
    chunks = [
      png_chunk("IHDR", header),
      (png_chunk("PLTE", palette) if palette),
      (png_chunk("tRNS", transparency) if transparency),
      png_chunk("IDAT", Zlib::Deflate.deflate(rows.join)),
      png_chunk("IEND", "")
    ].compact
    RTerm::Common::PngDecoder::SIGNATURE + chunks.join
  end

  def png_chunk(type, data)
    body = type + data
    [data.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
  end
end
