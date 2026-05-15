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
end
