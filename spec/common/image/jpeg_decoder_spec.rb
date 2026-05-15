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

  it "decodes 12-bit sequential grayscale JPEG pixels" do
    decoded = described_class.decode(twelve_bit_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 8, height: 8, precision: 12)
    expect(decoded[:pixels][0][0]).to eq([128, 128, 128, 255])
    expect(decoded[:pixels][7][7]).to eq([128, 128, 128, 255])
  end

  it "decodes progressive grayscale JPEG pixels" do
    decoded = described_class.decode(progressive_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 8, height: 8, progressive: true)
    expect(decoded[:pixels][0][0]).to eq([128, 128, 128, 255])
    expect(decoded[:pixels][7][7]).to eq([128, 128, 128, 255])
  end

  it "decodes CMYK JPEG pixels" do
    decoded = described_class.decode(cmyk_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 8, height: 8, components: 4, color_space: :cmyk)
    expect(decoded[:pixels][0][0]).to eq([191, 95, 95, 255])
  end

  it "decodes Adobe YCCK JPEG pixels" do
    decoded = described_class.decode(ycck_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 8, height: 8, components: 4, color_space: :ycck)
    expect(decoded[:pixels][0][0]).to eq([96, 96, 96, 255])
  end

  it "decodes lossless grayscale JPEG pixels" do
    decoded = described_class.decode(lossless_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 2, height: 1, lossless: true)
    expect(decoded[:pixels]).to eq([[[128, 128, 128, 255], [129, 129, 129, 255]]])
  end

  it "decodes sampled lossless grayscale JPEG pixels" do
    decoded = described_class.decode(sampled_lossless_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 2, height: 1, lossless: true)
    expect(decoded[:pixels]).to eq([[[128, 128, 128, 255], [129, 129, 129, 255]]])
  end

  it "decodes arithmetic JPEG conditioning metadata" do
    decoded = described_class.decode(arithmetic_jpeg_bytes)

    expect(decoded).to include(
      format: :sampled,
      media_type: :jpeg,
      width: 2,
      height: 1,
      arithmetic: true,
      conditioning: { dc: { 0 => 4 }, ac: { 0 => 2 } }
    )
  end

  it "decodes arithmetic grayscale JPEG pixels" do
    decoded = described_class.decode(arithmetic_scan_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 8, height: 8, arithmetic: true)
    expect(decoded[:pixels].map { |row| row.map(&:first) }).to eq(
      [
        [96, 104, 112, 120, 128, 136, 144, 152],
        [98, 106, 114, 122, 130, 138, 146, 154],
        [100, 108, 116, 124, 132, 140, 148, 156],
        [102, 110, 118, 126, 134, 142, 150, 158],
        [104, 112, 120, 128, 136, 144, 152, 160],
        [106, 114, 122, 130, 138, 146, 154, 162],
        [108, 116, 124, 132, 140, 148, 156, 164],
        [110, 118, 126, 134, 142, 150, 158, 166]
      ]
    )
  end

  it "decodes arithmetic progressive grayscale JPEG pixels" do
    decoded = described_class.decode(arithmetic_progressive_jpeg_bytes)

    expect(decoded).to include(format: :rgba, media_type: :jpeg, width: 8, height: 8, arithmetic: true, progressive: true)
    expect(decoded[:pixels].map { |row| row.map(&:first) }).to eq(
      [
        [96, 104, 112, 120, 128, 136, 144, 152],
        [98, 106, 114, 122, 130, 138, 146, 154],
        [100, 108, 116, 124, 132, 140, 148, 156],
        [102, 110, 118, 126, 134, 142, 150, 158],
        [104, 112, 120, 128, 136, 144, 152, 160],
        [106, 114, 122, 130, 138, 146, 154, 162],
        [108, 116, 124, 132, 140, 148, 156, 164],
        [110, 118, 126, 134, 142, 150, 158, 166]
      ]
    )
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

  def twelve_bit_jpeg_bytes
    [
      "\xff\xd8".b,
      jpeg_segment(0xdb, [0, *Array.new(64, 1)].pack("C*")),
      jpeg_segment(0xc1, [12, 8, 8, 1, 1, 0x11, 0].pack("CnnCCCC")),
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

  def ycck_jpeg_bytes
    [
      "\xff\xd8".b,
      jpeg_segment(0xee, "Adobe".b + [100, 0, 0, 0, 0, 2].pack("nCCCCC")),
      jpeg_segment(0xdb, [0, *Array.new(64, 255)].pack("C*")),
      jpeg_segment(0xc0, four_component_frame),
      jpeg_segment(0xc4, [0, 2, *Array.new(15, 0), 0, 2].pack("C*")),
      jpeg_segment(0xc4, [0x10, 1, *Array.new(15, 0), 0].pack("C*")),
      jpeg_segment(0xda, [4, 1, 0, 2, 0, 3, 0, 4, 0, 0, 63, 0].pack("C*")),
      "\x02\x00".b,
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

  def sampled_lossless_jpeg_bytes
    [
      "\xff\xd8".b,
      jpeg_segment(0xc3, [8, 1, 2, 1, 1, 0x21, 0].pack("CnnCCCC")),
      jpeg_segment(0xc4, [0, 1, 1, *Array.new(14, 0), 0, 1].pack("C*")),
      jpeg_segment(0xda, [1, 1, 0, 1, 0, 0].pack("C*")),
      "\x5f".b,
      "\xff\xd9".b
    ].join
  end

  def arithmetic_jpeg_bytes
    [
      "\xff\xd8".b,
      jpeg_segment(0xc9, [8, 1, 2, 1, 1, 0x11, 0].pack("CnnCCCC")),
      jpeg_segment(0xcc, [0, 4, 0x10, 2].pack("C*")),
      "\xff\xd9".b
    ].join
  end

  def arithmetic_scan_jpeg_bytes
    [
      0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
      0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0xff, 0xc9, 0x00, 0x0b, 0x08, 0x00, 0x08,
      0x00, 0x08, 0x01, 0x01, 0x11, 0x00, 0xff, 0xcc, 0x00, 0x06, 0x00, 0x10,
      0x10, 0x05, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00,
      0xd1, 0xd5, 0x9f, 0x93, 0x3d, 0xbe, 0xfb, 0x86, 0x79, 0x96, 0x69, 0x36,
      0xf0, 0xff, 0xd9
    ].pack("C*")
  end

  def arithmetic_progressive_jpeg_bytes
    [
      0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
      0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x01, 0x01, 0x01, 0xff, 0xca, 0x00, 0x0b, 0x08, 0x00, 0x08,
      0x00, 0x08, 0x01, 0x01, 0x11, 0x00, 0xff, 0xcc, 0x00, 0x04, 0x00, 0x10,
      0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x01, 0xd0, 0xb0,
      0xff, 0xcc, 0x00, 0x04, 0x10, 0x05, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01,
      0x00, 0x01, 0x05, 0x02, 0x16, 0x70, 0x55, 0xa0, 0xff, 0xcc, 0x00, 0x04,
      0x10, 0x05, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x06, 0x3f, 0x02,
      0x17, 0x01, 0x0c, 0xff, 0xcc, 0x00, 0x04, 0x10, 0x05, 0xff, 0xda, 0x00,
      0x08, 0x01, 0x01, 0x00, 0x01, 0x3f, 0x21, 0xa8, 0xb5, 0xff, 0xda, 0x00,
      0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x10, 0xff, 0xcc, 0x00, 0x04, 0x10,
      0x05, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x3f, 0x10, 0x24,
      0x5c, 0x31, 0xd3, 0xff, 0xd9
    ].pack("C*")
  end

  def four_component_frame
    [8, 8, 8, 4, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0, 4, 0x11, 0].pack("CnnCC12")
  end

  def jpeg_segment(marker, data)
    "\xff".b + marker.chr.b + [data.bytesize + 2].pack("n") + data
  end
end
