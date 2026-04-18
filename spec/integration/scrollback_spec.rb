# frozen_string_literal: true

RSpec.describe "scrollback behavior" do
  it "keeps recent scrollback and supports viewport scrolling" do
    terminal = RTerm::Terminal.new(cols: 20, rows: 3, scrollback: 5)

    8.times { |index| terminal.writeln("line #{index}") }

    active = terminal.buffer.active
    expect(active.y_base).to eq(5)
    expect(active.get_line(1).to_string).to eq("line 7")

    terminal.scroll_to_top
    expect(active.y_disp).to eq(0)

    terminal.scroll_to_bottom
    expect(active.y_disp).to eq(active.y_base)
  end
end
