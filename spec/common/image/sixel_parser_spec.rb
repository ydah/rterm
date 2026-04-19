# frozen_string_literal: true

RSpec.describe RTerm::Common::SixelParser do
  it "extracts raster attributes and estimates geometry" do
    image = described_class.parse('"1;1;10;12ABC-!3D', params: [1])

    expect(image).to include(protocol: :sixel, params: [1], data: '"1;1;10;12ABC-!3D')
    expect(image[:raster]).to eq(
      pan: 1,
      pad: 1,
      pixel_width: 10,
      pixel_height: 12
    )
    expect(image[:geometry]).to eq(cell_width: 3, pixel_height: 12)
  end
end
