# frozen_string_literal: true

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
end
