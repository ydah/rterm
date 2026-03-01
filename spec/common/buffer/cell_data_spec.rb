# frozen_string_literal: true

RSpec.describe RTerm::Common::CellData do
  describe "#initialize" do
    it "creates a cell with default values" do
      cell = described_class.new
      expect(cell.char).to eq("")
      expect(cell.width).to eq(1)
      expect(cell.fg).to eq(0)
      expect(cell.bg).to eq(0)
    end
  end

  describe "character access" do
    it "stores and retrieves a character" do
      cell = described_class.new
      cell.char = "A"
      expect(cell.char).to eq("A")
      expect(cell.code).to eq(65)
    end

    it "handles empty character" do
      cell = described_class.new
      cell.char = ""
      expect(cell.char).to eq("")
      expect(cell.code).to eq(0)
    end

    it "handles multi-byte characters" do
      cell = described_class.new
      cell.char = "漢"
      expect(cell.char).to eq("漢")
      expect(cell.code).to eq(0x6F22)
    end

    it "handles combined characters" do
      cell = described_class.new
      cell.combined_data = "é"
      expect(cell.char).to eq("é")
      expect(cell).to be_combined
    end
  end

  describe "width" do
    it "defaults to 1" do
      cell = described_class.new
      expect(cell.width).to eq(1)
    end

    it "can be set to 2 for wide characters" do
      cell = described_class.new
      cell.width = 2
      expect(cell.width).to eq(2)
    end

    it "can be set to 0 for zero-width characters" do
      cell = described_class.new
      cell.width = 0
      expect(cell.width).to eq(0)
    end
  end

  describe "attribute flags" do
    it "detects bold" do
      cell = described_class.new
      expect(cell).not_to be_bold
      cell.bold = true
      expect(cell).to be_bold
    end

    it "detects italic" do
      cell = described_class.new
      expect(cell).not_to be_italic
      cell.italic = true
      expect(cell).to be_italic
    end

    it "detects underline" do
      cell = described_class.new
      expect(cell).not_to be_underline
      cell.underline = true
      expect(cell).to be_underline
    end

    it "detects blink" do
      cell = described_class.new
      expect(cell).not_to be_blink
      cell.blink = true
      expect(cell).to be_blink
    end

    it "detects inverse" do
      cell = described_class.new
      expect(cell).not_to be_inverse
      cell.inverse = true
      expect(cell).to be_inverse
    end

    it "detects invisible" do
      cell = described_class.new
      expect(cell).not_to be_invisible
      cell.invisible = true
      expect(cell).to be_invisible
    end

    it "detects strikethrough" do
      cell = described_class.new
      expect(cell).not_to be_strikethrough
      cell.strikethrough = true
      expect(cell).to be_strikethrough
    end

    it "detects dim" do
      cell = described_class.new
      expect(cell).not_to be_dim
      cell.dim = true
      expect(cell).to be_dim
    end

    it "detects overline" do
      cell = described_class.new
      expect(cell).not_to be_overline
      cell.overline = true
      expect(cell).to be_overline
    end

    it "can unset flags" do
      cell = described_class.new
      cell.bold = true
      cell.bold = false
      expect(cell).not_to be_bold
    end
  end

  describe "foreground color" do
    it "defaults to default color" do
      cell = described_class.new
      expect(cell.fg_color_mode).to eq(:default)
    end

    it "sets 16-color palette" do
      cell = described_class.new
      cell.set_fg_color(:p16, 1) # red
      expect(cell.fg_color_mode).to eq(:p16)
      expect(cell.fg_color).to eq(1)
    end

    it "sets 256-color palette" do
      cell = described_class.new
      cell.set_fg_color(:p256, 196)
      expect(cell.fg_color_mode).to eq(:p256)
      expect(cell.fg_color).to eq(196)
    end

    it "sets TrueColor" do
      cell = described_class.new
      cell.set_fg_color(:rgb, 0xFF8000)
      expect(cell.fg_color_mode).to eq(:rgb)
      expect(cell.fg_color).to eq(0xFF8000)
      expect(cell.fg_red).to eq(0xFF)
      expect(cell.fg_green).to eq(0x80)
      expect(cell.fg_blue).to eq(0x00)
    end

    it "resets to default" do
      cell = described_class.new
      cell.set_fg_color(:p16, 1)
      cell.reset_fg_color
      expect(cell.fg_color_mode).to eq(:default)
    end
  end

  describe "background color" do
    it "defaults to default color" do
      cell = described_class.new
      expect(cell.bg_color_mode).to eq(:default)
    end

    it "sets TrueColor" do
      cell = described_class.new
      cell.set_bg_color(:rgb, 0x00FF00)
      expect(cell.bg_color_mode).to eq(:rgb)
      expect(cell.bg_color).to eq(0x00FF00)
      expect(cell.bg_red).to eq(0x00)
      expect(cell.bg_green).to eq(0xFF)
      expect(cell.bg_blue).to eq(0x00)
    end
  end

  describe "#clone" do
    it "creates a deep copy" do
      cell = described_class.new
      cell.char = "A"
      cell.width = 1
      cell.bold = true
      cell.set_fg_color(:rgb, 0xFF0000)

      copy = cell.clone
      expect(copy.char).to eq("A")
      expect(copy).to be_bold
      expect(copy.fg_color).to eq(0xFF0000)

      copy.char = "B"
      copy.bold = false
      expect(cell.char).to eq("A")
      expect(cell).to be_bold
    end
  end

  describe "#reset" do
    it "resets all attributes to defaults" do
      cell = described_class.new
      cell.char = "A"
      cell.bold = true
      cell.set_fg_color(:rgb, 0xFF0000)
      cell.reset
      expect(cell.char).to eq("")
      expect(cell).not_to be_bold
      expect(cell.fg_color_mode).to eq(:default)
    end
  end

  describe "#has_content?" do
    it "returns false for empty cell" do
      cell = described_class.new
      expect(cell).not_to have_content
    end

    it "returns true for cell with character" do
      cell = described_class.new
      cell.char = "A"
      expect(cell).to have_content
    end
  end
end
