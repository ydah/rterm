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
end
