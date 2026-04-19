# frozen_string_literal: true

RSpec.describe "terminal option behavior" do
  it "converts LF to CRLF when convert_eol is enabled" do
    terminal = RTerm::Terminal.new(cols: 10, rows: 3, convert_eol: true)

    terminal.write("a\nb")

    expect(terminal.buffer.active.get_line(0).to_string).to eq("a")
    expect(terminal.buffer.active.get_line(1).to_string).to eq("b")
  end

  it "does not emit input when stdin is disabled" do
    terminal = RTerm::Terminal.new(disable_stdin: true)
    received = nil
    terminal.on(:data) { |data| received = data }

    terminal.input("ignored")

    expect(received).to be_nil
  end

  it "resolves bold text to bright ANSI colors when enabled" do
    terminal = RTerm::Terminal.new(draw_bold_text_in_bright_colors: true)
    cell = RTerm::Common::CellData.new
    cell.bold = true
    cell.set_fg_color(:p16, 1)

    expect(terminal.cell_colors(cell)[:foreground]).to eq(RTerm::Theme.new.bright_red)
  end

  it "can disable bold-as-bright color resolution" do
    terminal = RTerm::Terminal.new(draw_bold_text_in_bright_colors: false)
    cell = RTerm::Common::CellData.new
    cell.bold = true
    cell.set_fg_color(:p16, 1)

    expect(terminal.cell_colors(cell)[:foreground]).to eq(RTerm::Theme.new.red)
  end

  it "adjusts foreground color to satisfy minimum contrast" do
    terminal = RTerm::Terminal.new(minimum_contrast_ratio: 7)
    cell = RTerm::Common::CellData.new
    cell.set_fg_color(:rgb, 0x111111)
    cell.set_bg_color(:rgb, 0x000000)

    expect(terminal.cell_colors(cell)[:foreground]).to eq("#ffffff")
  end

  it "honors transparency only when enabled" do
    opaque = RTerm::Terminal.new(allow_transparency: false)
    transparent = RTerm::Terminal.new(allow_transparency: true)
    cell = RTerm::Common::CellData.new
    opaque.internal.input_handler.color_manager.background = "transparent"
    transparent.internal.input_handler.color_manager.background = "transparent"

    expect(opaque.cell_colors(cell)[:background]).to eq(RTerm::Theme.new.background)
    expect(transparent.cell_colors(cell)[:background]).to eq("transparent")
  end

  it "exposes cursor width and inactive style policy" do
    terminal = RTerm::Terminal.new(cursor_width: 3, cursor_inactive_style: :bar)

    expect(terminal.cursor_info(active: false)).to include(style: :bar, blink: false, width: 3)
  end

  it "treats mac option as meta when configured" do
    terminal = RTerm::Terminal.new(mac_option_is_meta: true)
    received = nil
    terminal.on(:data) { |data| received = data }

    terminal.key_event("x", modifiers: [:option])

    expect(received).to eq("\ex")
  end

  it "emits screen reader and line update narration events" do
    terminal = RTerm::Terminal.new(screen_reader_mode: true)
    line_updates = []
    screen_reader = []
    terminal.on(:line_update) { |payload| line_updates << payload }
    terminal.on(:screen_reader) { |payload| screen_reader << payload }

    terminal.write("hello")

    expect(line_updates.last).to include(text: "hello")
    expect(screen_reader.last).to include(text: "hello")
  end
end
