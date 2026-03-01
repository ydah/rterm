# frozen_string_literal: true

RSpec.describe RTerm::Addon::Serialize do
  let(:terminal) { RTerm::Terminal.new(cols: 80, rows: 24) }
  let(:serializer) { described_class.new }

  before do
    terminal.load_addon(serializer)
  end

  describe "#serialize" do
    it "serializes plain text" do
      terminal.write("Hello World\r\n")
      result = serializer.serialize
      expect(result).to include("Hello World")
    end

    it "serializes text with attributes" do
      terminal.write("\e[1mBold\e[0m Normal\r\n")
      result = serializer.serialize
      expect(result).to include("\e[")
      expect(result).to include("Bold")
    end

    it "can recreate terminal state" do
      terminal.write("Hello \e[1;31mWorld\e[0m!\r\n")
      serialized = serializer.serialize

      # Create new terminal and replay
      term2 = RTerm::Terminal.new(cols: 80, rows: 24)
      term2.write(serialized)

      original_line = terminal.buffer.active.get_line(0).to_string
      replayed_line = term2.buffer.active.get_line(0).to_string
      expect(replayed_line).to eq(original_line)
    end
  end

  describe "#serialize_as_html" do
    it "generates HTML output" do
      terminal.write("Hello\r\n")
      html = serializer.serialize_as_html
      expect(html).to include("<pre>")
      expect(html).to include("Hello")
      expect(html).to include("</pre>")
    end

    it "includes color styles" do
      terminal.write("\e[31mRed\e[0m\r\n")
      html = serializer.serialize_as_html
      expect(html).to include("color:")
      expect(html).to include("Red")
    end
  end
end
