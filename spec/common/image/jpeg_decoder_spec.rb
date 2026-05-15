# frozen_string_literal: true

RSpec.describe RTerm::Common::JpegDecoder do
  it "decodes JPEG frame dimensions and component metadata" do
    decoded = described_class.decode(jpeg_bytes)

    expect(decoded).to include(
      format: :sampled,
      media_type: :jpeg,
      width: 2,
      height: 1,
      precision: 8,
      components: 3,
      progressive: false
    )
  end

  it "decodes baseline grayscale JPEG pixels" do
    decoded = described_class.decode(baseline_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 8, height: 8)
    expect(decoded[:pixels][0][0]).to eq([128, 128, 128, 255])
    expect(decoded[:pixels][7][7]).to eq([128, 128, 128, 255])
  end

  it "decodes progressive grayscale JPEG pixels" do
    decoded = described_class.decode(progressive_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 8, height: 8, progressive: true)
    expect(decoded[:pixels][0][0]).to eq([128, 128, 128, 255])
    expect(decoded[:pixels][7][7]).to eq([128, 128, 128, 255])
  end

  it "returns nil for unsupported bytes" do
    expect(described_class.decode("not-jpeg")).to be_nil
  end

  def jpeg_bytes
    frame = [
      8,
      1,
      2,
      3,
      1, 0x11, 0,
      2, 0x11, 1,
      3, 0x11, 1
    ].pack("CnnC9")
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

  def jpeg_segment(marker, data)
    "\xff".b + marker.chr.b + [data.bytesize + 2].pack("n") + data
  end
end
