# frozen_string_literal: true

RSpec.describe RTerm::Common::BufferLine do
  describe "#initialize" do
    it "creates a line with the specified number of columns" do
      line = described_class.new(80)
      expect(line.length).to eq(80)
    end

    it "fills with the given fill cell" do
      fill = RTerm::Common::CellData.new
      fill.char = "x"
      line = described_class.new(5, fill)
      expect(line.get_cell(0).char).to eq("x")
      expect(line.get_cell(4).char).to eq("x")
    end
  end

  describe "#get_cell / #set_cell" do
    it "sets and retrieves a cell" do
      line = described_class.new(80)
      cell = RTerm::Common::CellData.new
      cell.char = "A"
      cell.bold = true
      line.set_cell(5, cell)

      result = line.get_cell(5)
      expect(result.char).to eq("A")
      expect(result).to be_bold
    end
  end

  describe "#to_string" do
    it "returns the text content of the line" do
      line = described_class.new(10)
      "Hello".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        line.set_cell(i, cell)
      end
      expect(line.to_string).to eq("Hello")
    end

    it "trims trailing spaces by default" do
      line = described_class.new(10)
      "Hi".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        line.set_cell(i, cell)
      end
      expect(line.to_string).to eq("Hi")
    end

    it "does not trim when trim_right is false" do
      line = described_class.new(5)
      cell = RTerm::Common::CellData.new
      cell.char = "A"
      line.set_cell(0, cell)
      result = line.to_string(trim_right: false)
      expect(result.length).to eq(5)
    end

    it "supports start_col and end_col" do
      line = described_class.new(10)
      "Hello World".chars.first(10).each_with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        line.set_cell(i, cell)
      end
      expect(line.to_string(start_col: 0, end_col: 5)).to eq("Hello")
    end
  end

  describe "#get_trimmed_length" do
    it "returns the length excluding trailing empty cells" do
      line = described_class.new(10)
      "abc".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        line.set_cell(i, cell)
      end
      expect(line.get_trimmed_length).to eq(3)
    end

    it "returns 0 for an empty line" do
      line = described_class.new(10)
      expect(line.get_trimmed_length).to eq(0)
    end
  end

  describe "#insert_cells" do
    it "inserts blank cells at the given position" do
      line = described_class.new(10)
      "abcde".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        line.set_cell(i, cell)
      end
      fill = RTerm::Common::CellData.new
      line.insert_cells(2, 2, fill)
      expect(line.get_cell(0).char).to eq("a")
      expect(line.get_cell(1).char).to eq("b")
      expect(line.get_cell(2).char).to eq("")
      expect(line.get_cell(3).char).to eq("")
      expect(line.get_cell(4).char).to eq("c")
    end
  end

  describe "#delete_cells" do
    it "deletes cells at the given position and fills from the right" do
      line = described_class.new(10)
      "abcde".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        line.set_cell(i, cell)
      end
      fill = RTerm::Common::CellData.new
      line.delete_cells(1, 2, fill)
      expect(line.get_cell(0).char).to eq("a")
      expect(line.get_cell(1).char).to eq("d")
      expect(line.get_cell(2).char).to eq("e")
    end
  end

  describe "#replace_cells" do
    it "replaces cells in the given range" do
      line = described_class.new(10)
      "abcde".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        line.set_cell(i, cell)
      end
      fill = RTerm::Common::CellData.new
      fill.char = "x"
      line.replace_cells(1, 3, fill)
      expect(line.get_cell(0).char).to eq("a")
      expect(line.get_cell(1).char).to eq("x")
      expect(line.get_cell(2).char).to eq("x")
      expect(line.get_cell(3).char).to eq("d")
    end
  end

  describe "#resize" do
    it "pads with fill cells when expanding" do
      line = described_class.new(5)
      cell = RTerm::Common::CellData.new
      cell.char = "A"
      line.set_cell(0, cell)
      fill = RTerm::Common::CellData.new
      line.resize(10, fill)
      expect(line.length).to eq(10)
      expect(line.get_cell(0).char).to eq("A")
      expect(line.get_cell(9).char).to eq("")
    end

    it "truncates when shrinking" do
      line = described_class.new(10)
      "abcdefghij".each_char.with_index do |ch, i|
        cell = RTerm::Common::CellData.new
        cell.char = ch
        line.set_cell(i, cell)
      end
      fill = RTerm::Common::CellData.new
      line.resize(5, fill)
      expect(line.length).to eq(5)
      expect(line.get_cell(4).char).to eq("e")
    end
  end

  describe "#is_wrapped" do
    it "defaults to false" do
      line = described_class.new(80)
      expect(line.is_wrapped).to be false
    end

    it "can be set to true" do
      line = described_class.new(80)
      line.is_wrapped = true
      expect(line.is_wrapped).to be true
    end
  end

  describe "wide character handling" do
    it "handles width-2 characters" do
      line = described_class.new(10)
      cell = RTerm::Common::CellData.new
      cell.char = "漢"
      cell.width = 2
      line.set_cell(0, cell)

      expect(line.get_cell(0).char).to eq("漢")
      expect(line.get_cell(0).width).to eq(2)
    end

    it "creates the spacer cell for width-2 characters" do
      line = described_class.new(4)
      cell = RTerm::Common::CellData.new
      cell.char = "語"
      cell.width = 2

      line.set_cell(1, cell)

      expect(line.get_cell(1).char).to eq("語")
      expect(line.get_cell(1).width).to eq(2)
      expect(line.get_cell(2).char).to eq("")
      expect(line.get_cell(2).width).to eq(0)
    end

    it "clears the spacer when overwriting the left half" do
      line = described_class.new(4)
      wide = RTerm::Common::CellData.new
      wide.char = "語"
      wide.width = 2
      line.set_cell(0, wide)

      replacement = RTerm::Common::CellData.new
      replacement.char = "A"
      line.set_cell(0, replacement)

      expect(line.get_cell(0).char).to eq("A")
      expect(line.get_cell(0).width).to eq(1)
      expect(line.get_cell(1).char).to eq("")
      expect(line.get_cell(1).width).to eq(1)
    end

    it "clears the base when overwriting the right half" do
      line = described_class.new(4)
      wide = RTerm::Common::CellData.new
      wide.char = "語"
      wide.width = 2
      line.set_cell(0, wide)

      replacement = RTerm::Common::CellData.new
      replacement.char = "A"
      line.set_cell(1, replacement)

      expect(line.get_cell(0).char).to eq("")
      expect(line.get_cell(0).width).to eq(1)
      expect(line.get_cell(1).char).to eq("A")
      expect(line.get_cell(1).width).to eq(1)
    end

    it "does not leave a dangling spacer when inserting inside a wide character" do
      line = described_class.new(6)
      fill = RTerm::Common::CellData.new
      line.set_cell(0, RTerm::Common::CellData.new.tap { |cell| cell.char = "A" })
      line.set_cell(1, RTerm::Common::CellData.new.tap { |cell| cell.char = "語"; cell.width = 2 })
      line.set_cell(3, RTerm::Common::CellData.new.tap { |cell| cell.char = "B" })
      line.set_cell(4, RTerm::Common::CellData.new.tap { |cell| cell.char = "C" })

      line.insert_cells(2, 1, fill)

      expect(line.to_string).to eq("A   BC")
      expect((0...line.length).map { |x| line.get_cell(x).width }).to eq([1, 1, 1, 1, 1, 1])
    end

    it "does not leave a dangling spacer when deleting part of a wide character" do
      line = described_class.new(6)
      fill = RTerm::Common::CellData.new
      line.set_cell(0, RTerm::Common::CellData.new.tap { |cell| cell.char = "A" })
      line.set_cell(1, RTerm::Common::CellData.new.tap { |cell| cell.char = "語"; cell.width = 2 })
      line.set_cell(3, RTerm::Common::CellData.new.tap { |cell| cell.char = "B" })
      line.set_cell(4, RTerm::Common::CellData.new.tap { |cell| cell.char = "C" })

      line.delete_cells(1, 1, fill)

      expect(line.to_string).to eq("A BC")
      expect((0...line.length).map { |x| line.get_cell(x).width }).to eq([1, 1, 1, 1, 1, 1])
    end

    it "drops a width-2 character that would start in the final column" do
      line = described_class.new(4)
      cell = RTerm::Common::CellData.new
      cell.char = "語"
      cell.width = 2

      line.set_cell(3, cell)

      expect(line.get_cell(3).char).to eq("")
      expect(line.get_cell(3).width).to eq(1)
    end
  end
end
