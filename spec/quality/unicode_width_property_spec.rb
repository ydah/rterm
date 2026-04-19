# frozen_string_literal: true

RSpec.describe "unicode width properties" do
  it "keeps combining marks zero-width and printable ASCII single-width" do
    handler = RTerm::Common::UnicodeHandler.new

    (0x0300..0x036F).step(7) do |codepoint|
      expect(handler.char_width(codepoint.chr(Encoding::UTF_8))).to eq(0)
    end

    (" ".."~").each do |char|
      expect(handler.char_width(char)).to eq(1)
    end
  end

  it "keeps selected emoji presentation sequences wide" do
    handler = RTerm::Common::UnicodeHandler.new

    ["🙂", "🏳️‍🌈", "🇯🇵", "👍🏽"].each do |cluster|
      expect(handler.string_width(cluster)).to eq(2)
    end
  end
end
