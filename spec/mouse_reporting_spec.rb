# frozen_string_literal: true

RSpec.describe "mouse report generation" do
  let(:terminal) { RTerm::Terminal.new(cols: 80, rows: 24) }

  it "generates SGR mouse reports" do
    terminal.write("\e[?1006h\e[?1000h")
    received = nil
    terminal.on(:data) { |data| received = data }

    report = terminal.mouse_event(button: :left, col: 4, row: 2, event: :press)

    expect(report).to eq("\e[<0;5;3M")
    expect(received).to eq(report)
  end

  it "generates SGR release reports" do
    terminal.write("\e[?1006h\e[?1000h")

    expect(terminal.mouse_event(button: :left, col: 4, row: 2, event: :release)).to eq("\e[<0;5;3m")
  end

  it "generates X10 reports" do
    terminal.write("\e[?1000h")

    expect(terminal.mouse_event(button: :left, col: 0, row: 0, event: :press)).to eq("\e[M !!")
  end

  it "generates URXVT reports" do
    terminal.write("\e[?1015h\e[?1000h")

    expect(terminal.mouse_event(button: :wheel_up, col: 9, row: 4, event: :press)).to eq("\e[96;10;5M")
  end

  it "generates SGR pixel mouse reports" do
    terminal.write("\e[?1016h\e[?1000h")

    expect(
      terminal.mouse_event(button: :left, col: 1, row: 2, pixel_col: 13, pixel_row: 27)
    ).to eq("\e[<0;14;28M")
    expect(terminal.modes[:sgr_pixels_mode]).to be true
  end

  it "includes button and modifier compatibility bits" do
    terminal.write("\e[?1006h\e[?1003h")

    expect(
      terminal.mouse_event(button: :left, col: 0, row: 0, event: :motion, modifiers: %i[shift alt ctrl])
    ).to eq("\e[<60;1;1M")
  end

  it "uses wheel events when mouse tracking is enabled" do
    terminal.write("\e[?1006h\e[?1000h")

    expect(terminal.mouse_wheel(-1, col: 3, row: 4)).to eq("\e[<64;4;5M")
  end

  it "uses alternate scroll mode on the alternate buffer" do
    alt_terminal = RTerm::Terminal.new(cols: 80, rows: 24)
    received = nil
    alt_terminal.on(:data) { |data| received = data }
    alt_terminal.write("\e[?1049h")

    expect(alt_terminal.mouse_wheel(-2)).to eq("\e[A\e[A")
    expect(received).to eq("\e[A\e[A")
  end

  it "applies scroll sensitivity on the normal buffer" do
    scrolled = RTerm::Terminal.new(cols: 10, rows: 2, scrollback: 5, scroll_sensitivity: 2)
    scrolled.write("one\r\ntwo\r\nthree\r\nfour")

    expect(scrolled.mouse_wheel(-1)).to eq(-2)
    expect(scrolled.buffer.active.y_disp).to eq(scrolled.buffer.active.y_base - 2)
  end

  it "does not report mouse events when tracking is disabled" do
    expect(terminal.mouse_event(button: :left, col: 0, row: 0)).to be_nil
  end
end
