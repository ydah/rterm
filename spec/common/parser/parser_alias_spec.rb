# frozen_string_literal: true

RSpec.describe RTerm::Common::Parser do
  it "is the public parser alias for escape sequence parsing" do
    parser = described_class.new
    printed = nil
    parser.set_print_handler { |data| printed = data }

    parser.parse("ok")

    expect(printed).to eq("ok")
  end
end

RSpec.describe RTerm::Common::OscParser do
  it "splits OSC id and payload" do
    parsed = described_class.parse("2;hello")

    expect(parsed.id).to eq(2)
    expect(parsed.data).to eq("hello")
  end
end

RSpec.describe RTerm::Common::DcsParser do
  it "returns the identifier and payload" do
    parsed = described_class.parse("1;2$qpayload")

    expect(parsed.params).to eq([1, 2])
    expect(parsed.final).to eq("q")
    expect(parsed.data).to eq("payload")
  end
end
