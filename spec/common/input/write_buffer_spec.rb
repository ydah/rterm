# frozen_string_literal: true

RSpec.describe RTerm::Common::WriteBuffer do
  it "flushes written data in FIFO order" do
    received = +""
    buffer = described_class.new { |chunk| received << chunk }

    buffer.write("a")
    buffer.write("b")

    expect(received).to eq("ab")
    expect(buffer).to be_empty
  end

  it "can pause and resume flushing" do
    received = +""
    buffer = described_class.new(auto_flush: false) { |chunk| received << chunk }

    buffer.write("a")
    buffer.write("b")
    expect(received).to eq("")

    buffer.flush
    expect(received).to eq("ab")
  end

  it "raises when no consumer is provided" do
    buffer = described_class.new(auto_flush: false)
    buffer.write("data")

    expect { buffer.flush }.to raise_error(ArgumentError, /consumer/)
  end
end

RSpec.describe RTerm::Common::TextDecoder do
  it "decodes binary strings as UTF-8" do
    decoder = described_class.new
    data = "日本語".b

    expect(decoder.decode(data)).to eq("日本語")
    expect(decoder.decode(data).encoding).to eq(Encoding::UTF_8)
  end

  it "replaces invalid byte sequences" do
    decoder = described_class.new

    expect(decoder.decode("\xFF".b)).to eq("�")
  end
end
