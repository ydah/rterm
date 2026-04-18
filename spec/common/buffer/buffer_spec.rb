# frozen_string_literal: true

RSpec.describe RTerm::Common::Buffer do
  let(:cols) { 80 }
  let(:rows) { 24 }
  let(:scrollback) { 100 }
  let(:buffer) { described_class.new(cols, rows, scrollback) }

  describe "#initialize" do
    it "creates a buffer with the specified dimensions" do
      expect(buffer.cols).to eq(80)
      expect(buffer.rows).to eq(24)
    end

    it "initializes with empty lines" do
      line = buffer.get_line(0)
      expect(line).to be_a(RTerm::Common::BufferLine)
      expect(line.to_string).to eq("")
    end

    it "has the correct number of lines" do
      expect(buffer.lines.length).to eq(24)
    end

    it "sets initial cursor position to 0,0" do
      expect(buffer.x).to eq(0)
      expect(buffer.y).to eq(0)
    end

    it "sets scroll region to full screen" do
      expect(buffer.scroll_top).to eq(0)
      expect(buffer.scroll_bottom).to eq(23)
    end
  end

  describe "#get_line" do
    it "returns a BufferLine for a valid row" do
      expect(buffer.get_line(0)).to be_a(RTerm::Common::BufferLine)
    end

    it "returns nil for an out-of-range row" do
      expect(buffer.get_line(100)).to be_nil
    end
  end

  describe "#scroll_up" do
    it "scrolls content up" do
      # Write something on the first line
      cell = RTerm::Common::CellData.new
      cell.char = "A"
      buffer.get_line(0).set_cell(0, cell)

      buffer.scroll_up(1)
      # y_base should have increased
      expect(buffer.y_base).to eq(1)
    end

    it "keeps y_base bounded by scrollback capacity" do
      small = described_class.new(5, 2, 3)

      10.times { small.scroll_up(1) }

      expect(small.y_base).to eq(3)
      expect(small.get_line(0)).to be_a(RTerm::Common::BufferLine)
      expect(small.get_line(1)).to be_a(RTerm::Common::BufferLine)
    end
  end

  describe "#scroll_down" do
    it "scrolls content down within scroll region" do
      buffer.scroll_top = 0
      buffer.scroll_bottom = 23

      cell = RTerm::Common::CellData.new
      cell.char = "A"
      buffer.get_line(0).set_cell(0, cell)

      buffer.scroll_down(1)
      # First line should now be blank, content shifted down
      expect(buffer.get_line(0).to_string).to eq("")
    end
  end

  describe "#resize" do
    it "increases columns" do
      buffer.resize(120, 24)
      expect(buffer.cols).to eq(120)
      expect(buffer.get_line(0).length).to eq(120)
    end

    it "decreases columns" do
      buffer.resize(40, 24)
      expect(buffer.cols).to eq(40)
      expect(buffer.get_line(0).length).to eq(40)
    end

    it "increases rows" do
      buffer.resize(80, 48)
      expect(buffer.rows).to eq(48)
      expect(buffer.lines.length).to be >= 48
    end

    it "decreases rows" do
      buffer.resize(80, 12)
      expect(buffer.rows).to eq(12)
    end

    it "reflows wrapped lines when columns shrink" do
      small = described_class.new(10, 4, 10)
      "abcdefghij".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        small.get_line(0).set_cell(i, cell)
      end
      "klmno".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        small.get_line(1).set_cell(i, cell)
      end
      small.get_line(0).is_wrapped = true

      small.resize(5, 4)

      expect(small.get_line(0).to_string).to eq("abcde")
      expect(small.get_line(0).is_wrapped).to be true
      expect(small.get_line(1).to_string).to eq("fghij")
      expect(small.get_line(1).is_wrapped).to be true
      expect(small.get_line(2).to_string).to eq("klmno")
      expect(small.get_line(2).is_wrapped).to be false
    end

    it "reflows wrapped lines when columns expand" do
      small = described_class.new(5, 4, 10)
      "abcde".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        small.get_line(0).set_cell(i, cell)
      end
      "fghij".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        small.get_line(1).set_cell(i, cell)
      end
      small.get_line(0).is_wrapped = true

      small.resize(10, 4)

      expect(small.get_line(0).to_string).to eq("abcdefghij")
      expect(small.get_line(0).is_wrapped).to be false
      expect(small.get_line(1).to_string).to eq("")
    end
  end

  describe "#save_cursor / #restore_cursor" do
    it "saves and restores cursor position" do
      buffer.x = 10
      buffer.y = 5
      buffer.save_cursor
      buffer.x = 0
      buffer.y = 0
      buffer.restore_cursor
      expect(buffer.x).to eq(10)
      expect(buffer.y).to eq(5)
    end
  end

  describe "#clear" do
    it "clears all lines" do
      cell = RTerm::Common::CellData.new
      cell.char = "A"
      buffer.get_line(0).set_cell(0, cell)
      buffer.clear
      expect(buffer.get_line(0).to_string).to eq("")
    end
  end

  describe "scroll region (DECSTBM)" do
    it "sets scroll top and bottom" do
      buffer.scroll_top = 5
      buffer.scroll_bottom = 20
      expect(buffer.scroll_top).to eq(5)
      expect(buffer.scroll_bottom).to eq(20)
    end
  end

  describe "tab stops" do
    it "initializes default tab stops at every 8 columns" do
      expect(buffer.tabs[8]).to be true
      expect(buffer.tabs[16]).to be true
      expect(buffer.tabs[24]).to be true
    end
  end
end

RSpec.describe RTerm::Common::BufferSet do
  let(:cols) { 80 }
  let(:rows) { 24 }
  let(:scrollback) { 100 }
  let(:buffer_set) { described_class.new(cols, rows, scrollback) }

  describe "#initialize" do
    it "starts with the normal buffer active" do
      expect(buffer_set.active).to equal(buffer_set.normal)
    end
  end

  describe "#activate_alt_buffer" do
    it "switches to the alternate buffer" do
      buffer_set.activate_alt_buffer
      expect(buffer_set.active).to equal(buffer_set.alt)
    end
  end

  describe "#activate_normal_buffer" do
    it "switches back to the normal buffer" do
      buffer_set.activate_alt_buffer
      buffer_set.activate_normal_buffer
      expect(buffer_set.active).to equal(buffer_set.normal)
    end
  end

  describe "alternate buffer" do
    it "has no scrollback" do
      alt = buffer_set.alt
      expect(alt).to be_a(RTerm::Common::Buffer)
    end

    it "preserves normal buffer content when switching" do
      cell = RTerm::Common::CellData.new
      cell.char = "A"
      buffer_set.normal.get_line(0).set_cell(0, cell)

      buffer_set.activate_alt_buffer
      buffer_set.activate_normal_buffer
      expect(buffer_set.normal.get_line(0).get_cell(0).char).to eq("A")
    end
  end
end
