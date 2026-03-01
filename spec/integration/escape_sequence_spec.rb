# frozen_string_literal: true

RSpec.describe "Escape Sequence Integration" do
  let(:term) { RTerm::Terminal.new(cols: 80, rows: 24) }

  describe "C0 control characters" do
    it "handles CR LF combination" do
      term.write("Hello\r\nWorld")
      expect(term.buffer.active.get_line(0).to_string).to eq("Hello")
      expect(term.buffer.active.get_line(1).to_string).to eq("World")
    end

    it "handles BS to overwrite" do
      term.write("abc\x08X")
      expect(term.buffer.active.get_line(0).to_string).to eq("abX")
    end

    it "handles HT tab stops" do
      term.write("A\tB")
      line = term.buffer.active.get_line(0).to_string
      expect(line).to start_with("A")
      expect(line).to include("B")
      # B should be at tab stop 8
      expect(term.buffer.active.get_line(0).get_cell(8).char).to eq("B")
    end

    it "handles CR without LF" do
      term.write("Hello\rWorld")
      expect(term.buffer.active.get_line(0).to_string).to eq("World")
    end

    it "emits bell event on BEL" do
      called = false
      term.on(:bell) { called = true }
      term.write("\x07")
      expect(called).to be true
    end
  end

  describe "cursor movement" do
    it "CUP moves cursor to specified position" do
      term.write("\e[5;10Hx")
      expect(term.buffer.active.get_line(4).get_cell(9).char).to eq("x")
    end

    it "CUU moves cursor up" do
      term.write("\e[5;1H\e[2Ax")
      expect(term.buffer.active.get_line(2).get_cell(0).char).to eq("x")
    end

    it "CUD moves cursor down" do
      term.write("\e[1;1H\e[3Bx")
      expect(term.buffer.active.get_line(3).get_cell(0).char).to eq("x")
    end

    it "CUF moves cursor forward" do
      term.write("\e[1;1H\e[5Cx")
      expect(term.buffer.active.get_line(0).get_cell(5).char).to eq("x")
    end

    it "CUB moves cursor backward" do
      term.write("\e[1;10H\e[3Dx")
      expect(term.buffer.active.get_line(0).get_cell(6).char).to eq("x")
    end

    it "CHA moves cursor to absolute column" do
      term.write("\e[1;1H\e[20Gx")
      expect(term.buffer.active.get_line(0).get_cell(19).char).to eq("x")
    end

    it "VPA moves cursor to absolute row" do
      term.write("\e[10dx")
      expect(term.buffer.active.get_line(9).get_cell(0).char).to eq("x")
    end
  end

  describe "erasing" do
    before do
      term.write("ABCDEFGHIJ\r\n")
      term.write("KLMNOPQRST\r\n")
      term.write("UVWXYZ")
    end

    it "ED mode 0: erases from cursor to end of display" do
      term.write("\e[2;5H\e[0J")
      expect(term.buffer.active.get_line(0).to_string).to eq("ABCDEFGHIJ")
      expect(term.buffer.active.get_line(1).to_string).to eq("KLMN")
      expect(term.buffer.active.get_line(2).to_string).to eq("")
    end

    it "ED mode 2: erases entire display" do
      term.write("\e[2J")
      expect(term.buffer.active.get_line(0).to_string).to eq("")
      expect(term.buffer.active.get_line(1).to_string).to eq("")
    end

    it "EL mode 0: erases from cursor to end of line" do
      term.write("\e[1;5H\e[0K")
      expect(term.buffer.active.get_line(0).to_string).to eq("ABCD")
    end

    it "EL mode 1: erases from start of line to cursor" do
      term.write("\e[1;5H\e[1K")
      line = term.buffer.active.get_line(0).to_string
      expect(line[0..4]).to eq("     ")
      expect(line).to include("FGHIJ")
    end

    it "EL mode 2: erases entire line" do
      term.write("\e[1;1H\e[2K")
      expect(term.buffer.active.get_line(0).to_string).to eq("")
    end

    it "ECH erases characters without moving cursor" do
      term.write("\e[1;3H\e[3X")
      line = term.buffer.active.get_line(0)
      expect(line.get_cell(0).char).to eq("A")
      expect(line.get_cell(1).char).to eq("B")
      expect(line.get_cell(2)).not_to have_content
    end
  end

  describe "line operations" do
    it "IL inserts blank lines" do
      term.write("Line 1\r\nLine 2\r\nLine 3")
      term.write("\e[2;1H\e[1L")
      expect(term.buffer.active.get_line(0).to_string).to eq("Line 1")
      expect(term.buffer.active.get_line(1).to_string).to eq("")
      expect(term.buffer.active.get_line(2).to_string).to eq("Line 2")
    end

    it "DL deletes lines" do
      term.write("Line 1\r\nLine 2\r\nLine 3")
      term.write("\e[2;1H\e[1M")
      expect(term.buffer.active.get_line(0).to_string).to eq("Line 1")
      expect(term.buffer.active.get_line(1).to_string).to eq("Line 3")
    end

    it "ICH inserts blank characters" do
      term.write("ABCDE\e[1;3H\e[2@")
      line = term.buffer.active.get_line(0)
      expect(line.get_cell(0).char).to eq("A")
      expect(line.get_cell(1).char).to eq("B")
      expect(line.get_cell(4).char).to eq("C")
    end

    it "DCH deletes characters" do
      term.write("ABCDE\e[1;2H\e[2P")
      line = term.buffer.active.get_line(0)
      expect(line.get_cell(0).char).to eq("A")
      expect(line.get_cell(1).char).to eq("D")
    end
  end

  describe "scrolling" do
    it "SU scrolls content up" do
      3.times { |i| term.writeln("Line #{i}") }
      term.write("\e[1S")
      expect(term.buffer.active.get_line(0).to_string).to eq("Line 1")
    end

    it "SD scrolls content down" do
      3.times { |i| term.writeln("Line #{i}") }
      term.write("\e[1T")
      expect(term.buffer.active.get_line(0).to_string).to eq("")
    end

    it "DECSTBM sets scroll region" do
      term.write("\e[5;20r")
      expect(term.buffer.active.scroll_top).to eq(4)
      expect(term.buffer.active.scroll_bottom).to eq(19)
    end
  end

  describe "SGR attributes" do
    it "sets bold" do
      term.write("\e[1mBold\e[0m")
      expect(term.buffer.active.get_line(0).get_cell(0)).to be_bold
    end

    it "sets italic" do
      term.write("\e[3mItalic\e[0m")
      expect(term.buffer.active.get_line(0).get_cell(0)).to be_italic
    end

    it "sets ANSI foreground color" do
      term.write("\e[31mRed\e[0m")
      cell = term.buffer.active.get_line(0).get_cell(0)
      expect(cell.fg_color_mode).to eq(:p16)
      expect(cell.fg_color).to eq(1)
    end

    it "sets 256-color foreground" do
      term.write("\e[38;5;196mColor\e[0m")
      cell = term.buffer.active.get_line(0).get_cell(0)
      expect(cell.fg_color_mode).to eq(:p256)
      expect(cell.fg_color).to eq(196)
    end

    it "sets TrueColor foreground" do
      term.write("\e[38;2;255;128;0mOrange\e[0m")
      cell = term.buffer.active.get_line(0).get_cell(0)
      expect(cell.fg_color_mode).to eq(:rgb)
      expect(cell.fg_red).to eq(255)
      expect(cell.fg_green).to eq(128)
      expect(cell.fg_blue).to eq(0)
    end

    it "resets all attributes with SGR 0" do
      term.write("\e[1;3;4mStyled\e[0mPlain")
      cell = term.buffer.active.get_line(0).get_cell(6) # 'P' in Plain
      expect(cell).not_to be_bold
      expect(cell).not_to be_italic
      expect(cell).not_to be_underline
    end

    it "sets and resets individual attributes" do
      term.write("\e[1;3mBI\e[22mI\e[23mN")
      line = term.buffer.active.get_line(0)
      expect(line.get_cell(0)).to be_bold
      expect(line.get_cell(0)).to be_italic
      expect(line.get_cell(2)).not_to be_bold
      expect(line.get_cell(2)).to be_italic
      expect(line.get_cell(3)).not_to be_italic
    end
  end

  describe "DEC private modes" do
    it "alternate buffer switch and restore" do
      term.write("Normal content")
      term.write("\e[?1049h")
      expect(term.buffer.active).to eq(term.buffer.alt)
      term.write("Alt content")
      term.write("\e[?1049l")
      expect(term.buffer.active).to eq(term.buffer.normal)
      expect(term.buffer.active.get_line(0).to_string).to eq("Normal content")
    end

    it "DECTCEM hides and shows cursor" do
      term.write("\e[?25l")
      expect(term.internal.input_handler.cursor_hidden).to be true
      term.write("\e[?25h")
      expect(term.internal.input_handler.cursor_hidden).to be false
    end

    it "bracketed paste mode" do
      term.write("\e[?2004h")
      expect(term.internal.input_handler.bracketed_paste_mode).to be true
      term.write("\e[?2004l")
      expect(term.internal.input_handler.bracketed_paste_mode).to be false
    end
  end

  describe "save/restore cursor" do
    it "DECSC/DECRC saves and restores position" do
      term.write("\e[5;10H\e7")
      term.write("\e[1;1HOverwrite")
      term.write("\e8X")
      expect(term.buffer.active.get_line(4).get_cell(9).char).to eq("X")
    end

    it "reverse index scrolls down at top" do
      term.write("\e[1;1H\eM")
      expect(term.buffer.active.get_line(0).to_string).to eq("")
    end
  end

  describe "OSC sequences" do
    it "sets title with OSC 0" do
      received = nil
      term.on(:title_change) { |t| received = t }
      term.write("\e]0;My Terminal\x07")
      expect(received).to eq("My Terminal")
    end

    it "sets title with OSC 2" do
      received = nil
      term.on(:title_change) { |t| received = t }
      term.write("\e]2;Window Title\x07")
      expect(received).to eq("Window Title")
    end
  end

  describe "real-world scenarios" do
    it "simulates ls --color output" do
      term.write("\e[0m\e[01;34mdir1\e[0m  \e[01;32mexec\e[0m  \e[0mfile.txt\e[0m\r\n")
      line = term.buffer.active.get_line(0)
      expect(line.to_string).to include("dir1")
      expect(line.to_string).to include("exec")
      expect(line.to_string).to include("file.txt")
      expect(line.get_cell(0)).to be_bold
    end

    it "simulates vim-like screen" do
      term.write("\e[2J\e[H\e[?1049h")
      term.write("File content\r\n")
      term.write("\e[24;1H\e[7m-- INSERT --\e[0m")
      last_line = term.buffer.active.get_line(23)
      expect(last_line.to_string).to include("INSERT")
      expect(last_line.get_cell(0)).to be_inverse
    end

    it "simulates progress bar with CR overwrite" do
      10.times do |i|
        pct = (i + 1) * 10
        bar = "#" * (pct / 5) + " " * (20 - pct / 5)
        term.write("\r[#{bar}] #{pct}%")
      end
      line = term.buffer.active.get_line(0)
      expect(line.to_string).to include("100%")
      expect(line.to_string).to include("[####################]")
    end

    it "handles rapid scrolling output" do
      100.times { |i| term.writeln("Output line #{i}") }
      # Should not crash and visible lines should contain recent output
      # Row 22 has the last written line (row 23 is blank after writeln moves cursor down)
      line = term.buffer.active.get_line(22)
      expect(line.to_string).to match(/Output line \d+/)
    end

    it "handles mixed text and escape sequences" do
      term.write("Hello \e[1;31mWorld\e[0m \e[4mUnderlined\e[24m end\r\n")
      line = term.buffer.active.get_line(0)
      expect(line.to_string).to eq("Hello World Underlined end")
      expect(line.get_cell(6)).to be_bold   # 'W' in World
      expect(line.get_cell(12)).to be_underline  # 'U' in Underlined
      expect(line.get_cell(23)).not_to be_underline # 'e' in end
    end
  end
end
