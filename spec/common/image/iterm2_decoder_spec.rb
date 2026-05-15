# frozen_string_literal: true

require "zlib"

RSpec.describe RTerm::Common::Iterm2Decoder do
  it "decodes base64 image payloads and preserves attributes" do
    image = {
      protocol: :iterm2,
      attributes: {
        "name" => ["test.png"].pack("m0"),
        "inline" => "1",
        "width" => "3",
        "height" => "2"
      },
      data: ["PNG"].pack("m0")
    }

    decoded = described_class.decode(image)

    expect(decoded).to include(
      protocol: :iterm2,
      format: :binary,
      bytes: "PNG",
      byte_size: 3,
      name: "test.png",
      width: "3",
      height: "2",
      inline: true
    )
  end

  it "decodes inline PNG pixels when the payload is a PNG image" do
    image = {
      protocol: :iterm2,
      attributes: {
        "name" => ["pixel.png"].pack("m0"),
        "inline" => "1",
        "width" => "1",
        "height" => "1"
      },
      data: [png_bytes].pack("m0")
    }

    decoded = described_class.decode(image)

    expect(decoded).to include(
      protocol: :iterm2,
      format: :rgba,
      media_type: :png,
      byte_size: png_bytes.bytesize,
      name: "pixel.png",
      width: 1,
      height: 1,
      inline: true
    )
    expect(decoded[:pixels]).to eq([[[255, 0, 0, 255]]])
  end

  it "decodes inline GIF pixels when the payload is a GIF image" do
    image = {
      protocol: :iterm2,
      attributes: { "inline" => "1" },
      data: [gif_bytes].pack("m0")
    }

    decoded = described_class.decode(image)

    expect(decoded).to include(protocol: :iterm2, format: :rgba, media_type: :gif, width: 1, height: 1)
    expect(decoded[:pixels]).to eq([[[255, 0, 0, 255]]])
  end

  it "decodes inline JPEG dimensions when the payload is a JPEG image" do
    image = {
      protocol: :iterm2,
      attributes: { "inline" => "1" },
      data: [jpeg_bytes].pack("m0")
    }

    decoded = described_class.decode(image)

    expect(decoded).to include(protocol: :iterm2, format: :sampled, media_type: :jpeg, width: 2, height: 1)
  end

  it "decodes inline baseline JPEG pixels when entropy data is supported" do
    image = {
      protocol: :iterm2,
      attributes: { "inline" => "1" },
      data: [baseline_jpeg_bytes].pack("m0")
    }

    decoded = described_class.decode(image)

    expect(decoded).to include(protocol: :iterm2, format: :rgba, media_type: :jpeg, width: 8, height: 8)
    expect(decoded[:pixels][0][0]).to eq([128, 128, 128, 255])
  end

  it "decodes inline progressive JPEG pixels when entropy data is supported" do
    image = {
      protocol: :iterm2,
      attributes: { "inline" => "1" },
      data: [progressive_jpeg_bytes].pack("m0")
    }

    decoded = described_class.decode(image)

    expect(decoded).to include(protocol: :iterm2, format: :rgba, media_type: :jpeg, width: 8, height: 8)
    expect(decoded[:pixels][0][0]).to eq([128, 128, 128, 255])
  end

  it "decodes inline CMYK JPEG pixels when entropy data is supported" do
    image = {
      protocol: :iterm2,
      attributes: { "inline" => "1" },
      data: [cmyk_jpeg_bytes].pack("m0")
    }

    decoded = described_class.decode(image)

    expect(decoded).to include(protocol: :iterm2, format: :rgba, media_type: :jpeg, width: 8, height: 8)
    expect(decoded[:pixels][0][0]).to eq([191, 95, 95, 255])
  end

  it "decodes inline lossless JPEG pixels when entropy data is supported" do
    image = {
      protocol: :iterm2,
      attributes: { "inline" => "1" },
      data: [lossless_jpeg_bytes].pack("m0")
    }

    decoded = described_class.decode(image)

    expect(decoded).to include(protocol: :iterm2, format: :rgba, media_type: :jpeg, width: 2, height: 1)
    expect(decoded[:pixels]).to eq([[[128, 128, 128, 255], [129, 129, 129, 255]]])
  end

  def png_bytes
    header = [1, 1, 8, 6, 0, 0, 0].pack("NNCCCCC")
    row = [0, 255, 0, 0, 255].pack("C*")
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

  def baseline_jpeg_bytes
    [
      "\xff\xd8".b,
      jpeg_segment(0xdb, [0, *Array.new(64, 1)].pack("C*")),
      jpeg_segment(0xc0, [8, 8, 8, 1, 1, 0x11, 0].pack("CnnCCCC")),
      jpeg_segment(0xc4, [0, 1, *Array.new(15, 0), 0].pack("C*")),
      jpeg_segment(0xc4, [0x10, 1, *Array.new(15, 0), 0].pack("C*")),
      jpeg_segment(0xda, [1, 1, 0, 0, 63, 0].pack("C*")),
      "\x3f".b,
      "\xff\xd9".b
    ].join
  end

  def progressive_jpeg_bytes
    [
      "\xff\xd8".b,
      jpeg_segment(0xdb, [0, *Array.new(64, 1)].pack("C*")),
      jpeg_segment(0xc2, [8, 8, 8, 1, 1, 0x11, 0].pack("CnnCCCC")),
      jpeg_segment(0xc4, [0, 1, *Array.new(15, 0), 0].pack("C*")),
      jpeg_segment(0xc4, [0x10, 1, *Array.new(15, 0), 0].pack("C*")),
      jpeg_segment(0xda, [1, 1, 0, 0, 0, 0].pack("C*")),
      "\x7f".b,
      jpeg_segment(0xda, [1, 1, 0, 1, 63, 0].pack("C*")),
      "\x7f".b,
      "\xff\xd9".b
    ].join
  end

  def cmyk_jpeg_bytes
    [
      "\xff\xd8".b,
      jpeg_segment(0xdb, [0, *Array.new(64, 255)].pack("C*")),
      jpeg_segment(0xc0, four_component_frame),
      jpeg_segment(0xc4, [0, 2, *Array.new(15, 0), 0, 2].pack("C*")),
      jpeg_segment(0xc4, [0x10, 1, *Array.new(15, 0), 0].pack("C*")),
      jpeg_segment(0xda, [4, 1, 0, 2, 0, 3, 0, 4, 0, 0, 63, 0].pack("C*")),
      "\x80\x80".b,
      "\xff\xd9".b
    ].join
  end

  def lossless_jpeg_bytes
    [
      "\xff\xd8".b,
      jpeg_segment(0xc3, [8, 1, 2, 1, 1, 0x11, 0].pack("CnnCCCC")),
      jpeg_segment(0xc4, [0, 1, 1, *Array.new(14, 0), 0, 1].pack("C*")),
      jpeg_segment(0xda, [1, 1, 0, 1, 0, 0].pack("C*")),
      "\x5f".b,
      "\xff\xd9".b
    ].join
  end

  def four_component_frame
    [8, 8, 8, 4, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0, 4, 0x11, 0].pack("CnnCC12")
  end

  def jpeg_segment(marker, data)
    "\xff".b + marker.chr.b + [data.bytesize + 2].pack("n") + data
  end
end
