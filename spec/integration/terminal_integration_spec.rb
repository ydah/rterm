# frozen_string_literal: true

RSpec.describe RTerm::Terminal do
  let(:terminal) { described_class.new(cols: 80, rows: 24) }

  describe "#initialize" do
    it "creates a terminal with specified dimensions" do
      expect(terminal.cols).to eq(80)
      expect(terminal.rows).to eq(24)
    end

    it "defaults to 80x24" do
      t = described_class.new
      expect(t.cols).to eq(80)
      expect(t.rows).to eq(24)
    end
  end

  describe "#write and #writeln" do
    it "writes text to the buffer" do
      terminal.write("Hello")
      expect(terminal.buffer.active.get_line(0).to_string).to eq("Hello")
    end

    it "handles writeln" do
      terminal.writeln("First")
      terminal.writeln("Second")
      expect(terminal.buffer.active.get_line(0).to_string).to eq("First")
      expect(terminal.buffer.active.get_line(1).to_string).to eq("Second")
    end
  end

  describe "#buffer" do
    it "provides access to active buffer" do
      expect(terminal.buffer.active).to be_a(RTerm::Common::Buffer)
    end

    it "provides access to normal buffer" do
      expect(terminal.buffer.normal).to be_a(RTerm::Common::Buffer)
    end

    it "provides access to alt buffer" do
      expect(terminal.buffer.alt).to be_a(RTerm::Common::Buffer)
    end
  end

  describe "#parser" do
    it "registers custom parser handlers" do
      received = nil
      disposable = terminal.parser.register_osc_handler(1337) { |data| received = data }

      terminal.write("\e]1337;custom\x07")
      expect(received).to eq("custom")

      disposable.dispose
      terminal.write("\e]1337;ignored\x07")
      expect(received).to eq("custom")
    end
  end

  describe "#unicode" do
    it "registers a unicode provider that affects rendering width" do
      terminal.unicode.register("narrow", ->(_codepoint) { 1 })
      terminal.unicode.active_version = "narrow"

      terminal.write("🚀X")
      expect(terminal.buffer.active.get_line(0).get_cell(1).char).to eq("X")
    end
  end

  describe "#modes" do
    it "reports current xterm-style terminal modes" do
      terminal.write("\e[4h")
      terminal.write("\e[?1h")
      terminal.write("\e[?6h")
      terminal.write("\e=")
      terminal.write("\e[?2004h")

      expect(terminal.modes).to include(
        application_cursor_keys_mode: true,
        application_keypad_mode: true,
        bracketed_paste_mode: true,
        insert_mode: true,
        origin_mode: true,
        wraparound_mode: true
      )
    end
  end

  describe "#input" do
    it "emits data event for PTY forwarding" do
      received = nil
      terminal.on(:data) { |data| received = data }
      terminal.input("ls -la\r")
      expect(received).to eq("ls -la\r")
    end
  end

  describe "#resize" do
    it "resizes the terminal" do
      terminal.resize(120, 40)
      expect(terminal.cols).to eq(120)
      expect(terminal.rows).to eq(40)
    end
  end

  describe "#clear and #reset" do
    it "clears the buffer" do
      terminal.write("Hello")
      terminal.clear
      expect(terminal.buffer.active.get_line(0).to_string).to eq("")
    end

    it "resets the terminal" do
      terminal.write("Hello")
      terminal.reset
      expect(terminal.buffer.active.get_line(0).to_string).to eq("")
    end
  end

  describe "#on" do
    it "registers event listeners" do
      called = false
      terminal.on(:bell) { called = true }
      terminal.write("\x07")
      expect(called).to be true
    end
  end

  describe "addon system" do
    it "loads and disposes addons" do
      addon = Class.new do
        attr_reader :activated, :disposed

        def activate(terminal)
          @activated = true
          @terminal = terminal
        end

        def dispose
          @disposed = true
        end
      end.new

      terminal.load_addon(addon)
      expect(addon.activated).to be true

      terminal.dispose
      expect(addon.disposed).to be true
    end
  end

  describe "escape sequence integration" do
    it "handles cursor movement and text" do
      terminal.write("\e[5;10HHello")
      line = terminal.buffer.active.get_line(4) # 5th row (0-based: 4)
      expect(line.to_string.strip).to include("Hello")
    end

    it "handles SGR colors" do
      terminal.write("\e[38;2;255;0;0mRed\e[0m")
      cell = terminal.buffer.active.get_line(0).get_cell(0)
      expect(cell.char).to eq("R")
      expect(cell.fg_color_mode).to eq(:rgb)
      expect(cell.fg_red).to eq(255)
      expect(cell.fg_green).to eq(0)
      expect(cell.fg_blue).to eq(0)
    end

    it "handles alternate buffer switch" do
      terminal.write("Normal")
      terminal.write("\e[?1049h") # Switch to alt buffer
      terminal.write("Alt")
      expect(terminal.buffer.active).to eq(terminal.buffer.alt)

      terminal.write("\e[?1049l") # Switch back
      expect(terminal.buffer.active).to eq(terminal.buffer.normal)
      expect(terminal.buffer.normal.get_line(0).to_string).to eq("Normal")
    end

    it "handles scrolling" do
      24.times { |i| terminal.writeln("Line #{i}") }
      terminal.writeln("Line 24") # This should cause scroll
      # The first line should have scrolled up
      expect(terminal.buffer.active.get_line(0).to_string).not_to eq("Line 0")
    end

    it "handles insert mode and origin mode" do
      terminal.write("ABCD")
      terminal.write("\e[1;3H\e[4hX")
      expect(terminal.buffer.active.get_line(0).to_string).to eq("ABXCD")

      terminal.write("\e[5;10r\e[?6h\e[1;1HY")
      expect(terminal.buffer.active.get_line(4).get_cell(0).char).to eq("Y")
    end
  end
end
