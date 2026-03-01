# frozen_string_literal: true

RSpec.describe RTerm::Headless::HeadlessTerminal do
  let(:terminal) { described_class.new(cols: 80, rows: 24) }

  describe "#initialize" do
    it "creates a terminal with specified dimensions" do
      expect(terminal.cols).to eq(80)
      expect(terminal.rows).to eq(24)
    end
  end

  describe "#write" do
    it "writes text to the buffer" do
      terminal.write("Hello World")
      line = terminal.get_line(0)
      expect(line.to_string).to eq("Hello World")
    end

    it "handles ANSI color sequences" do
      terminal.write("\e[1;31mRed\e[0m")
      line = terminal.get_line(0)
      expect(line.to_string).to eq("Red")
      expect(line.get_cell(0)).to be_bold
    end
  end

  describe "#writeln" do
    it "writes text with a newline" do
      terminal.writeln("Line 1")
      terminal.writeln("Line 2")
      expect(terminal.get_line(0).to_string).to eq("Line 1")
      expect(terminal.get_line(1).to_string).to eq("Line 2")
    end
  end

  describe "#buffer" do
    it "returns the active buffer" do
      expect(terminal.buffer).to be_a(RTerm::Common::Buffer)
    end
  end

  describe "#resize" do
    it "changes terminal dimensions" do
      terminal.resize(120, 40)
      expect(terminal.cols).to eq(120)
      expect(terminal.rows).to eq(40)
    end
  end

  describe "#clear" do
    it "clears the buffer" do
      terminal.write("Hello")
      terminal.clear
      expect(terminal.get_line(0).to_string).to eq("")
    end
  end

  describe "#reset" do
    it "resets the terminal" do
      terminal.write("\e[1mBold\e[0m")
      terminal.reset
      expect(terminal.get_line(0).to_string).to eq("")
    end
  end

  describe "events" do
    it "emits :bell on BEL character" do
      called = false
      terminal.on(:bell) { called = true }
      terminal.write("\x07")
      expect(called).to be true
    end

    it "emits :title_change on OSC title" do
      received = nil
      terminal.on(:title_change) { |title| received = title }
      terminal.write("\e]0;My Title\x07")
      expect(received).to eq("My Title")
    end

    it "emits :resize on resize" do
      resize_data = nil
      terminal.on(:resize) { |data| resize_data = data }
      terminal.resize(120, 40)
      expect(resize_data).to eq({ cols: 120, rows: 40 })
    end
  end

  describe "spec §11.1 usage example" do
    it "handles the basic headless usage example" do
      term = described_class.new(cols: 80, rows: 24)
      term.write("Hello \e[1;31mWorld\e[0m!\r\n")
      line = term.get_line(0)
      expect(line.to_string).to eq("Hello World!")
    end
  end
end
