# frozen_string_literal: true

RSpec.describe RTerm::Common::SixelDecoder do
  it "decodes sixel data into an indexed pixel matrix" do
    image = RTerm::Common::SixelParser.parse('"1;1;4;6#2;2;100;0;0!2A', params: [])
    decoded = described_class.decode(image)

    expect(decoded).to include(
      protocol: :sixel,
      format: :indexed_rgba,
      width: 4,
      height: 6
    )
    expect(decoded[:palette][2]).to eq([255, 0, 0, 255])
    expect(decoded[:pixels][1][0, 2]).to eq([2, 2])
  end
end
