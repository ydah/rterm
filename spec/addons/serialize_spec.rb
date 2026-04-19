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

    it "includes requested scrollback lines" do
      small = RTerm::Terminal.new(cols: 10, rows: 2, scrollback: 3)
      small_serializer = described_class.new
      small.load_addon(small_serializer)
      4.times { |index| small.writeln("line#{index}") }

      result = small_serializer.serialize(scrollback: 2)

      expect(result).to include("line1")
      expect(result).to include("line3")
    end

    it "can exclude the alternate buffer" do
      terminal.write("normal")
      terminal.write("\e[?1049h")
      terminal.write("alt")

      expect(serializer.serialize(exclude_alt_buffer: true)).to include("normal")
      expect(serializer.serialize(exclude_alt_buffer: true)).not_to include("alt")
    end

    it "can exclude mode sequences" do
      terminal.write("\e[?7l")

      expect(serializer.serialize).to include("\e[?7l")
      expect(serializer.serialize(exclude_modes: true)).not_to include("\e[?7l")
    end

    it "serializes extended terminal modes" do
      terminal.write("\e[?1h\e=\e[?12h\e[?45h\e[?1002h\e[?1006h\e[?1004h\e[?2004h")

      serialized = serializer.serialize
      replayed = RTerm::Terminal.new(cols: 80, rows: 24)
      replayed.write(serialized)

      expect(replayed.modes).to include(
        application_cursor_keys_mode: true,
        application_keypad_mode: true,
        cursor_blink: true,
        reverse_wraparound_mode: true,
        mouse_tracking_mode: :button,
        sgr_mouse_mode: true,
        focus_event_mode: true,
        bracketed_paste_mode: true
      )
    end

    it "serializes title and icon name state" do
      terminal.write("\e]1;Icon\a")
      terminal.write("\e]2;Title\a")

      serialized = serializer.serialize
      replayed = RTerm::Terminal.new(cols: 80, rows: 24)
      replayed.write(serialized)

      expect(serialized).to include("\e]1;Icon\a")
      expect(serialized).to include("\e]2;Title\a")
      expect(replayed.icon_name).to eq("Icon")
      expect(replayed.title).to eq("Title")
    end

    it "serializes cursor style" do
      terminal.write("\e[6 q")

      serialized = serializer.serialize
      replayed = RTerm::Terminal.new(cols: 80, rows: 24)
      replayed.write(serialized)

      expect(serialized).to include("\e[6 q")
      expect(replayed.internal.input_handler.cursor_style).to eq(:bar)
    end

    it "serializes dynamic colors and palette overrides" do
      terminal.write("\e]10;#eeeeee\a")
      terminal.write("\e]11;#111111\a")
      terminal.write("\e]12;#00ff00\a")
      terminal.write("\e]4;1;#ff1111\a")

      serialized = serializer.serialize
      replayed = RTerm::Terminal.new(cols: 80, rows: 24)
      replayed.write(serialized)
      colors = replayed.internal.input_handler.color_manager

      expect(colors.foreground).to eq("#eeeeee")
      expect(colors.background).to eq("#111111")
      expect(colors.cursor).to eq("#00ff00")
      expect(colors.palette[1]).to eq("#ff1111")
    end

    it "serializes OSC 8 link metadata" do
      terminal.write("\e]8;id=1;https://example.com\aLink\e]8;;\a")

      serialized = serializer.serialize
      replayed = RTerm::Terminal.new(cols: 80, rows: 24)
      replayed.write(serialized)
      link = replayed.buffer.active.get_line(0).get_cell(0).link

      expect(serialized).to include("\e]8;id=1;https://example.com\a")
      expect(link).to eq({ params: "id=1", uri: "https://example.com" })
    end

    it "serializes image protocol payloads" do
      terminal.write("\ePqABCDEF\e\\")
      terminal.write("\e]1337;File=name=test.png;inline=1:AAAA\a")

      serialized = serializer.serialize
      replayed = RTerm::Terminal.new(cols: 80, rows: 24)
      replayed.write(serialized)

      expect(serialized).to include("\ePqABCDEF\e\\")
      expect(serialized).to include("\e]1337;File=name=test.png;inline=1:AAAA\a")
      expect(replayed.images.map { |image| image[:protocol] }).to include(:sixel, :iterm2)
    end

    it "can serialize normal and alternate buffers together" do
      terminal.write("normal")
      terminal.write("\e[?1049h")
      terminal.write("alt")
      terminal.write("\e[?1049l")

      serialized = serializer.serialize(include_alt_buffer: true)
      replayed = RTerm::Terminal.new(cols: 80, rows: 24)
      replayed.write(serialized)

      expect(replayed.buffer.active).to eq(replayed.buffer.normal)
      expect(replayed.buffer.normal.get_line(0).to_string).to include("normal")
      expect(replayed.buffer.alt.get_line(0).to_string).to include("alt")
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
