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

  it "does not report mouse events when tracking is disabled" do
    expect(terminal.mouse_event(button: :left, col: 0, row: 0)).to be_nil
  end
end
