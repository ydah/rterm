# frozen_string_literal: true

RSpec.describe RTerm::Common::InputHandler do
  let(:cols) { 80 }
  let(:rows) { 24 }
  let(:buffer_set) { RTerm::Common::BufferSet.new(cols, rows) }
  let(:parser) { RTerm::Common::EscapeSequenceParser.new }
  let(:handler) { described_class.new(buffer_set, parser) }
  let(:buffer) { buffer_set.active }

  before { handler }

  def parse(data)
    parser.parse(data)
  end

  def line_text(y)
    buffer.get_line(y).to_string(trim_right: true)
  end

  def cell_at(x, y)
    buffer.get_line(y).get_cell(x)
  end

  describe "print handler" do
    it "writes characters to the buffer at the cursor position" do
      parse("Hello")
      expect(line_text(0)).to eq("Hello")
      expect(buffer.x).to eq(5)
    end

    it "overwrites existing characters" do
      parse("AAAA")
      buffer.x = 0
      parse("BB")
      expect(line_text(0)).to eq("BBAA")
    end

    it "handles multi-byte UTF-8 characters" do
      parse("日本語")
      expect(line_text(0)).to eq("日本語")
    end

    it "prints emoji variation sequences as one wide cell" do
      parse("a©\uFE0Fb")

      expect(line_text(0)).to eq("a©️b")
      expect(cell_at(1, 0).char).to eq("©\uFE0F")
      expect(cell_at(1, 0).width).to eq(2)
      expect(cell_at(2, 0).width).to eq(0)
      expect(buffer.x).to eq(4)
    end
  end

  describe "autowrap" do
    it "wraps cursor to next line when reaching end of line" do
      parse("A" * cols)
      expect(buffer.x).to eq(cols)
      parse("B")
      expect(buffer.y).to eq(1)
      expect(buffer.x).to eq(1)
      expect(line_text(1)).to eq("B")
    end

    it "does not wrap when DECAWM is disabled" do
      parse("\e[?7l") # disable autowrap
      parse("A" * (cols + 5))
      expect(buffer.y).to eq(0)
      expect(buffer.x).to eq(cols - 1)
    end
  end

  describe "C0 control characters" do
    describe "BEL (0x07)" do
      it "emits a :bell event" do
        bell_received = false
        handler.on(:bell) { bell_received = true }
        parse("\x07")
        expect(bell_received).to be true
      end
    end

    describe "BS (0x08)" do
      it "moves cursor left by one" do
        buffer.x = 5
        parse("\x08")
        expect(buffer.x).to eq(4)
      end

      it "does not move cursor below 0" do
        buffer.x = 0
        parse("\x08")
        expect(buffer.x).to eq(0)
      end
    end

    describe "HT (0x09)" do
      it "moves to the next tab stop" do
        buffer.x = 0
        parse("\t")
        expect(buffer.x).to eq(8)
      end

      it "moves from mid-tab to next tab stop" do
        buffer.x = 3
        parse("\t")
        expect(buffer.x).to eq(8)
      end
    end

    describe "LF (0x0A)" do
      it "moves cursor down by one line" do
        buffer.y = 0
        parse("\n")
        expect(buffer.y).to eq(1)
      end

      it "scrolls buffer when at the bottom of scroll region" do
        buffer.y = rows - 1
        parse("first line")
        buffer.x = 0
        buffer.y = rows - 1
        parse("\n")
        expect(buffer.y).to eq(rows - 1)
      end
    end

    describe "VT (0x0B) and FF (0x0C)" do
      it "acts like LF" do
        buffer.y = 0
        parse("\x0B")
        expect(buffer.y).to eq(1)

        parse("\x0C")
        expect(buffer.y).to eq(2)
      end
    end

    describe "CR (0x0D)" do
      it "moves cursor to column 0" do
        buffer.x = 10
        parse("\r")
        expect(buffer.x).to eq(0)
      end
    end
  end

  describe "CSI sequences" do
    describe "CUU (A) - cursor up" do
      it "moves cursor up" do
        buffer.y = 5
        parse("\e[3A")
        expect(buffer.y).to eq(2)
      end

      it "defaults to 1" do
        buffer.y = 5
        parse("\e[A")
        expect(buffer.y).to eq(4)
      end

      it "stops at scroll top" do
        buffer.y = 2
        parse("\e[10A")
        expect(buffer.y).to eq(0)
      end
    end

    describe "CUD (B) - cursor down" do
      it "moves cursor down" do
        buffer.y = 0
        parse("\e[3B")
        expect(buffer.y).to eq(3)
      end

      it "stops at scroll bottom" do
        buffer.y = 0
        parse("\e[100B")
        expect(buffer.y).to eq(rows - 1)
      end
    end

    describe "CUF (C) - cursor forward" do
      it "moves cursor right" do
        buffer.x = 0
        parse("\e[5C")
        expect(buffer.x).to eq(5)
      end

      it "stops at right margin" do
        buffer.x = 0
        parse("\e[200C")
        expect(buffer.x).to eq(cols - 1)
      end
    end

    describe "CUB (D) - cursor backward" do
      it "moves cursor left" do
        buffer.x = 10
        parse("\e[3D")
        expect(buffer.x).to eq(7)
      end

      it "stops at column 0" do
        buffer.x = 2
        parse("\e[10D")
        expect(buffer.x).to eq(0)
      end
    end

    describe "CNL (E) - cursor next line" do
      it "moves down and returns to column 0" do
        buffer.x = 10
        buffer.y = 2
        parse("\e[3E")
        expect(buffer.x).to eq(0)
        expect(buffer.y).to eq(5)
      end
    end

    describe "CPL (F) - cursor preceding line" do
      it "moves up and returns to column 0" do
        buffer.x = 10
        buffer.y = 5
        parse("\e[3F")
        expect(buffer.x).to eq(0)
        expect(buffer.y).to eq(2)
      end
    end

    describe "CUP (H) - cursor position" do
      it "moves cursor to 1-based position (converted to 0-based)" do
        parse("\e[5;10H")
        expect(buffer.y).to eq(4)
        expect(buffer.x).to eq(9)
      end

      it "defaults to 1;1 (home)" do
        buffer.x = 10
        buffer.y = 10
        parse("\e[H")
        expect(buffer.y).to eq(0)
        expect(buffer.x).to eq(0)
      end

      it "clamps to buffer dimensions" do
        parse("\e[999;999H")
        expect(buffer.y).to eq(rows - 1)
        expect(buffer.x).to eq(cols - 1)
      end
    end

    describe "ED (J) - erase in display" do
      before do
        rows.times do |y|
          buffer.x = 0
          buffer.y = y if y > 0
          parse("Line #{y}".ljust(cols))
          buffer.y = y
        end
        buffer.x = 5
        buffer.y = 5
      end

      it "mode 0: erases from cursor to end of display" do
        parse("\e[0J")
        expect(line_text(4)).to eq("Line 4".ljust(cols).rstrip)
        expect(cell_at(0, 5).char).to eq("L")
        expect(cell_at(4, 5).char).to eq(" ")
        expect(cell_at(5, 5).char).to eq("")
        expect(line_text(6)).to eq("")
      end

      it "mode 1: erases from start of display to cursor" do
        parse("\e[1J")
        expect(line_text(0)).to eq("")
        expect(line_text(4)).to eq("")
        # line 5 cols 0..5 should be erased
        expect(cell_at(0, 5).char).to eq("")
        expect(line_text(6)).to eq("Line 6".ljust(cols).rstrip)
      end

      it "mode 2: erases entire display" do
        parse("\e[2J")
        rows.times do |y|
          expect(line_text(y)).to eq("")
        end
      end
    end

    describe "EL (K) - erase in line" do
      before do
        parse("Hello, World!")
        buffer.x = 5
      end

      it "mode 0: erases from cursor to end of line" do
        parse("\e[0K")
        expect(line_text(0)).to eq("Hello")
      end

      it "mode 1: erases from start of line to cursor" do
        parse("\e[1K")
        expect(cell_at(0, 0).char).to eq("")
        expect(cell_at(4, 0).char).to eq("")
        expect(cell_at(5, 0).char).to eq("")
        expect(cell_at(6, 0).char).to eq(" ")
        expect(cell_at(7, 0).char).to eq("W")
      end

      it "mode 2: erases entire line" do
        parse("\e[2K")
        expect(line_text(0)).to eq("")
      end
    end

    describe "IL (L) - insert lines" do
      before do
        3.times do |i|
          buffer.x = 0
          buffer.y = i
          parse("Line #{i}")
        end
        buffer.y = 1
      end

      it "inserts blank lines at cursor row" do
        parse("\e[1L")
        expect(line_text(0)).to eq("Line 0")
        expect(line_text(1)).to eq("")
        expect(line_text(2)).to eq("Line 1")
        expect(line_text(3)).to eq("Line 2")
      end
    end

    describe "DL (M) - delete lines" do
      before do
        3.times do |i|
          buffer.x = 0
          buffer.y = i
          parse("Line #{i}")
        end
        buffer.y = 1
      end

      it "deletes lines at cursor row" do
        parse("\e[1M")
        expect(line_text(0)).to eq("Line 0")
        expect(line_text(1)).to eq("Line 2")
        expect(line_text(2)).to eq("")
      end
    end

    describe "ICH (@) - insert characters" do
      it "inserts blank characters at cursor" do
        parse("ABCDE")
        buffer.x = 2
        parse("\e[2@")
        expect(line_text(0)).to eq("AB  CDE")
      end
    end

    describe "DCH (P) - delete characters" do
      it "deletes characters at cursor" do
        parse("ABCDE")
        buffer.x = 1
        parse("\e[2P")
        expect(line_text(0)).to eq("ADE")
      end
    end

    describe "SU (S) - scroll up" do
      it "scrolls content up" do
        parse("Line 0\r\nLine 1\r\nLine 2")
        parse("\e[1S")
        expect(line_text(0)).to eq("Line 1")
        expect(line_text(1)).to eq("Line 2")
      end
    end

    describe "SD (T) - scroll down" do
      it "scrolls content down" do
        parse("Line 0\r\nLine 1\r\nLine 2")
        parse("\e[1T")
        expect(line_text(0)).to eq("")
        expect(line_text(1)).to eq("Line 0")
        expect(line_text(2)).to eq("Line 1")
      end
    end

    describe "ECH (X) - erase characters" do
      it "erases characters at cursor without moving cursor" do
        parse("ABCDE")
        buffer.x = 1
        parse("\e[3X")
        expect(line_text(0)).to eq("A   E")
        expect(buffer.x).to eq(1)
      end
    end

    describe "VPA (d) - vertical position absolute" do
      it "moves cursor to absolute row (1-based)" do
        parse("\e[5d")
        expect(buffer.y).to eq(4)
      end
    end

    describe "CHA (G) - cursor horizontal absolute" do
      it "moves cursor to absolute column (1-based)" do
        parse("\e[10G")
        expect(buffer.x).to eq(9)
      end
    end

    describe "HPA (`) - horizontal position absolute" do
      it "moves cursor to absolute column (1-based)" do
        parse("\e[12`")
        expect(buffer.x).to eq(11)
      end
    end

    describe "HPR (a) - horizontal position relative" do
      it "moves cursor to the right" do
        buffer.x = 3
        parse("\e[5a")
        expect(buffer.x).to eq(8)
      end
    end

    describe "HVP (f) - horizontal vertical position" do
      it "works like CUP" do
        parse("\e[5;10f")
        expect(buffer.y).to eq(4)
        expect(buffer.x).to eq(9)
      end
    end

    describe "CHT (I) - cursor forward tabulation" do
      it "moves to the next tab stops" do
        buffer.x = 1
        parse("\e[2I")
        expect(buffer.x).to eq(16)
      end
    end

    describe "CBT (Z) - cursor backward tabulation" do
      it "moves to the previous tab stops" do
        buffer.x = 17
        parse("\e[2Z")
        expect(buffer.x).to eq(8)
      end
    end

    describe "REP (b) - repeat previous character" do
      it "repeats the last printed character" do
        parse("A\e[4b")
        expect(line_text(0)).to eq("AAAAA")
      end
    end

    describe "VPR (e) - vertical position relative" do
      it "moves cursor down relative to the current row" do
        buffer.y = 2
        parse("\e[5e")
        expect(buffer.y).to eq(7)
      end
    end

    describe "TBC (g) - tab clear" do
      it "clears the current tab stop" do
        buffer.x = 8
        parse("\e[g")
        buffer.x = 1
        parse("\e[I")
        expect(buffer.x).to eq(16)
      end

      it "clears all tab stops with mode 3" do
        parse("\e[3g")
        buffer.x = 1
        parse("\e[I")
        expect(buffer.x).to eq(cols - 1)
      end
    end

    describe "DECSTBM (r) - set scroll region" do
      it "sets scroll region" do
        parse("\e[5;20r")
        expect(buffer.scroll_top).to eq(4)
        expect(buffer.scroll_bottom).to eq(19)
      end

      it "resets scroll region with no params" do
        parse("\e[5;20r")
        parse("\e[r")
        expect(buffer.scroll_top).to eq(0)
        expect(buffer.scroll_bottom).to eq(rows - 1)
      end
    end

    describe "SM/RM (h/l) - standard modes" do
      it "enables and disables insert mode" do
        parse("ABCD")
        buffer.x = 2

        parse("\e[4hX")
        expect(line_text(0)).to eq("ABXCD")
        expect(handler.insert_mode).to be true

        parse("\e[4l")
        expect(handler.insert_mode).to be false
      end
    end
  end

  describe "SGR (m) - set graphic rendition" do
    it "sets bold" do
      parse("\e[1mA")
      expect(cell_at(0, 0).bold?).to be true
    end

    it "sets dim" do
      parse("\e[2mA")
      expect(cell_at(0, 0).dim?).to be true
    end

    it "sets italic" do
      parse("\e[3mA")
      expect(cell_at(0, 0).italic?).to be true
    end

    it "sets underline" do
      parse("\e[4mA")
      expect(cell_at(0, 0).underline?).to be true
    end

    it "sets blink" do
      parse("\e[5mA")
      expect(cell_at(0, 0).blink?).to be true
    end

    it "sets inverse" do
      parse("\e[7mA")
      expect(cell_at(0, 0).inverse?).to be true
    end

    it "sets invisible" do
      parse("\e[8mA")
      expect(cell_at(0, 0).invisible?).to be true
    end

    it "sets strikethrough" do
      parse("\e[9mA")
      expect(cell_at(0, 0).strikethrough?).to be true
    end

    it "sets overline" do
      parse("\e[53mA")
      expect(cell_at(0, 0).overline?).to be true
    end

    it "resets all with SGR 0" do
      parse("\e[1;3;4mA\e[0mB")
      expect(cell_at(0, 0).bold?).to be true
      expect(cell_at(1, 0).bold?).to be false
      expect(cell_at(1, 0).italic?).to be false
      expect(cell_at(1, 0).underline?).to be false
    end

    it "resets individual attributes" do
      parse("\e[1;3;4m")
      parse("\e[22mA")
      expect(cell_at(0, 0).bold?).to be false
      expect(cell_at(0, 0).italic?).to be true
      expect(cell_at(0, 0).underline?).to be true

      parse("\e[23mB")
      expect(cell_at(1, 0).italic?).to be false

      parse("\e[24mC")
      expect(cell_at(2, 0).underline?).to be false
    end

    describe "ANSI 8 colors" do
      it "sets foreground color 30-37" do
        parse("\e[31mA") # red
        cell = cell_at(0, 0)
        expect(cell.fg_color_mode).to eq(:p16)
        expect(cell.fg_color).to eq(1)
      end

      it "sets background color 40-47" do
        parse("\e[42mA") # green bg
        cell = cell_at(0, 0)
        expect(cell.bg_color_mode).to eq(:p16)
        expect(cell.bg_color).to eq(2)
      end

      it "sets bright foreground 90-97" do
        parse("\e[91mA") # bright red
        cell = cell_at(0, 0)
        expect(cell.fg_color_mode).to eq(:p16)
        expect(cell.fg_color).to eq(9) # 91 - 90 + 8
      end

      it "sets bright background 100-107" do
        parse("\e[101mA") # bright red bg
        cell = cell_at(0, 0)
        expect(cell.bg_color_mode).to eq(:p16)
        expect(cell.bg_color).to eq(9)
      end

      it "resets foreground with 39" do
        parse("\e[31mA\e[39mB")
        expect(cell_at(0, 0).fg_color_mode).to eq(:p16)
        expect(cell_at(1, 0).fg_color_mode).to eq(:default)
      end

      it "resets background with 49" do
        parse("\e[42mA\e[49mB")
        expect(cell_at(0, 0).bg_color_mode).to eq(:p16)
        expect(cell_at(1, 0).bg_color_mode).to eq(:default)
      end
    end

    describe "256 colors" do
      it "sets foreground 256 color with 38;5;N" do
        parse("\e[38;5;196mA")
        cell = cell_at(0, 0)
        expect(cell.fg_color_mode).to eq(:p256)
        expect(cell.fg_color).to eq(196)
      end

      it "sets background 256 color with 48;5;N" do
        parse("\e[48;5;82mA")
        cell = cell_at(0, 0)
        expect(cell.bg_color_mode).to eq(:p256)
        expect(cell.bg_color).to eq(82)
      end
    end

    describe "TrueColor" do
      it "sets foreground TrueColor with 38;2;R;G;B" do
        parse("\e[38;2;100;150;200mA")
        cell = cell_at(0, 0)
        expect(cell.fg_color_mode).to eq(:rgb)
        expect(cell.fg_red).to eq(100)
        expect(cell.fg_green).to eq(150)
        expect(cell.fg_blue).to eq(200)
      end

      it "sets background TrueColor with 48;2;R;G;B" do
        parse("\e[48;2;50;100;150mA")
        cell = cell_at(0, 0)
        expect(cell.bg_color_mode).to eq(:rgb)
        expect(cell.bg_red).to eq(50)
        expect(cell.bg_green).to eq(100)
        expect(cell.bg_blue).to eq(150)
      end
    end
  end

  describe "ESC sequences" do
    describe "IND/NEL/HTS (D/E/H)" do
      it "ESC D acts like index" do
        buffer.y = 0
        parse("\eD")
        expect(buffer.y).to eq(1)
      end

      it "ESC E moves to the next line and column 0" do
        buffer.x = 10
        buffer.y = 0
        parse("\eE")
        expect(buffer.x).to eq(0)
        expect(buffer.y).to eq(1)
      end

      it "ESC H sets a tab stop at the current column" do
        parse("\e[3g")
        buffer.x = 5
        parse("\eH")
        buffer.x = 0
        parse("\e[I")
        expect(buffer.x).to eq(5)
      end
    end

    describe "DECKPAM/DECKPNM (=/> ) - keypad mode" do
      it "toggles application keypad mode" do
        parse("\e=")
        expect(handler.application_keypad_mode).to be true

        parse("\e>")
        expect(handler.application_keypad_mode).to be false
      end
    end

    describe "DECSC/DECRC (7/8) - save/restore cursor" do
      it "saves and restores cursor position" do
        buffer.x = 10
        buffer.y = 5
        parse("\e7")
        buffer.x = 0
        buffer.y = 0
        parse("\e8")
        expect(buffer.x).to eq(10)
        expect(buffer.y).to eq(5)
      end

      it "saves and restores attributes" do
        parse("\e[1m") # bold
        parse("\e7")
        parse("\e[0m") # reset
        parse("\e8")
        parse("A")
        expect(cell_at(0, 0).bold?).to be true
      end
    end

    describe "RI (M) - reverse index" do
      it "moves cursor up one line" do
        buffer.y = 5
        parse("\eM")
        expect(buffer.y).to eq(4)
      end

      it "scrolls down when at top of scroll region" do
        parse("Line 0\r\nLine 1\r\nLine 2")
        buffer.y = 0
        parse("\eM")
        expect(buffer.y).to eq(0)
        expect(line_text(0)).to eq("")
        expect(line_text(1)).to eq("Line 0")
      end
    end

    describe "RIS (c) - full reset" do
      it "resets the buffer and cursor" do
        parse("Hello")
        buffer.y = 5
        parse("\ec")
        expect(buffer.x).to eq(0)
        expect(buffer.y).to eq(0)
        expect(handler.autowrap).to be true
      end
    end
  end

  describe "OSC sequences" do
    it "sets title with OSC 0" do
      title = nil
      handler.on(:title_change) { |t| title = t }
      parse("\e]0;My Title\x07")
      expect(title).to eq("My Title")
    end

    it "sets title with OSC 2" do
      title = nil
      handler.on(:title_change) { |t| title = t }
      parse("\e]2;Another Title\x07")
      expect(title).to eq("Another Title")
    end
  end

  describe "DEC private modes" do
    describe "DECCKM (1) - application cursor keys" do
      it "enables and disables application cursor keys mode" do
        parse("\e[?1h")
        expect(handler.application_cursor_keys_mode).to be true

        parse("\e[?1l")
        expect(handler.application_cursor_keys_mode).to be false
      end
    end

    describe "DECOM (6) - origin mode" do
      it "moves CUP relative to the scroll region when enabled" do
        parse("\e[5;10r")
        parse("\e[?6h")
        parse("\e[1;1H")
        expect(buffer.y).to eq(4)
        expect(handler.origin_mode).to be true
      end

      it "returns to absolute positioning when disabled" do
        parse("\e[5;10r")
        parse("\e[?6h")
        parse("\e[?6l")
        parse("\e[1;1H")
        expect(buffer.y).to eq(0)
        expect(handler.origin_mode).to be false
      end
    end

    describe "DECTCEM (25) - cursor visibility" do
      it "hides cursor" do
        parse("\e[?25l")
        expect(handler.cursor_hidden).to be true
      end

      it "shows cursor" do
        parse("\e[?25l")
        parse("\e[?25h")
        expect(handler.cursor_hidden).to be false
      end
    end

    describe "DECAWM (7) - autowrap" do
      it "disables autowrap" do
        parse("\e[?7l")
        expect(handler.autowrap).to be false
      end

      it "enables autowrap" do
        parse("\e[?7l")
        parse("\e[?7h")
        expect(handler.autowrap).to be true
      end
    end

    describe "cursor blink mode (12)" do
      it "toggles cursor blink mode" do
        parse("\e[?12h")
        expect(handler.cursor_blink).to be true

        parse("\e[?12l")
        expect(handler.cursor_blink).to be false
      end
    end

    describe "reverse wraparound mode (45)" do
      it "moves back to the previous wrapped row on backspace" do
        parse("\e[?45h")
        parse("x" * cols)
        expect(buffer.x).to eq(cols)

        parse("y")
        expect(buffer.y).to eq(1)
        expect(buffer.x).to eq(1)

        buffer.x = 0
        parse("\b")

        expect(buffer.y).to eq(0)
        expect(buffer.x).to eq(cols - 1)
      end
    end

    describe "Bracketed paste mode (2004)" do
      it "enables bracketed paste mode" do
        parse("\e[?2004h")
        expect(handler.bracketed_paste_mode).to be true
      end

      it "disables bracketed paste mode" do
        parse("\e[?2004h")
        parse("\e[?2004l")
        expect(handler.bracketed_paste_mode).to be false
      end
    end

    describe "Alternate buffer (47, 1047, 1049)" do
      it "switches to alternate buffer" do
        parse("\e[?1049h")
        expect(buffer_set.active).to eq(buffer_set.alt)
      end

      it "switches back to normal buffer" do
        parse("\e[?1049h")
        parse("\e[?1049l")
        expect(buffer_set.active).to eq(buffer_set.normal)
      end

      it "clears the alternate buffer on entry" do
        buffer_set.alt.get_line(0).set_cell(0, RTerm::Common::CellData.new.tap { |cell| cell.char = "X" })
        parse("\e[?1049h")

        expect(buffer_set.alt.get_line(0).to_string).to eq("")
        expect(buffer_set.alt.x).to eq(0)
        expect(buffer_set.alt.y).to eq(0)
      end

      it "restores the normal buffer cursor when leaving 1049 mode" do
        buffer.x = 5
        buffer.y = 3
        parse("\e[?1049h")

        buffer_set.alt.x = 0
        buffer_set.alt.y = 0

        parse("\e[?1049l")

        expect(buffer_set.normal.x).to eq(5)
        expect(buffer_set.normal.y).to eq(3)
      end
    end

    describe "Save/restore cursor mode (1048)" do
      it "restores cursor position and attributes" do
        buffer.x = 4
        buffer.y = 2
        parse("\e[31m")
        parse("\e[?1048h")

        buffer.x = 0
        buffer.y = 0
        parse("\e[32m")
        parse("\e[?1048lX")

        cell = buffer.get_line(2).get_cell(4)
        expect(cell.char).to eq("X")
        expect(cell.fg_color_mode).to eq(:p16)
        expect(cell.fg_color).to eq(1)
      end
    end
  end

  describe "save/restore cursor" do
    it "supports CSI s/u" do
      buffer.x = 7
      buffer.y = 5
      parse("\e[s")

      buffer.x = 0
      buffer.y = 0
      parse("\e[u")

      expect(buffer.x).to eq(7)
      expect(buffer.y).to eq(5)
    end
  end

  describe "DSR (n) - device status report" do
    it "emits operating status report for param 5" do
      response = nil
      handler.on(:data) { |d| response = d }
      parse("\e[5n")
      expect(response).to eq("\e[0n")
    end

    it "emits cursor position report for param 6" do
      buffer.x = 9
      buffer.y = 4
      response = nil
      handler.on(:data) { |d| response = d }
      parse("\e[6n")
      expect(response).to eq("\e[5;10R")
    end

    it "emits DEC extended cursor position report" do
      buffer.x = 2
      buffer.y = 1
      response = nil
      handler.on(:data) { |d| response = d }
      parse("\e[?6n")
      expect(response).to eq("\e[?2;3R")
    end
  end

  describe "DA (c) - device attributes" do
    it "emits primary device attributes" do
      response = nil
      handler.on(:data) { |d| response = d }
      parse("\e[c")
      expect(response).to eq("\e[?1;2c")
    end

    it "emits secondary device attributes" do
      response = nil
      handler.on(:data) { |d| response = d }
      parse("\e[>c")
      expect(response).to eq("\e[>0;276;0c")
    end
  end
end
