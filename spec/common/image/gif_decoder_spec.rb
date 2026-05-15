# frozen_string_literal: true

RSpec.describe RTerm::Common::GifDecoder do
  it "decodes the first GIF frame into RGBA pixels" do
    decoded = described_class.decode(gif_bytes)

    expect(decoded).to include(format: :rgba, media_type: :gif, width: 1, height: 1)
    expect(decoded[:pixels]).to eq([[[255, 0, 0, 255]]])
  end

  it "returns nil for unsupported bytes" do
    expect(described_class.decode("not-gif")).to be_nil
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
end
