# frozen_string_literal: true

RSpec.describe "resize reflow properties" do
  it "preserves logical text while changing dimensions" do
    terminal = RTerm::Terminal.new(cols: 10, rows: 5, scrollback: 20)
    text = "alpha beta gamma delta epsilon"
    terminal.write(text)

    terminal.resize(7, 5)
    terminal.resize(14, 5)

    terminal.select_all
    expect(terminal.selection.delete(" \r\n")).to include(text.delete(" "))
  end
end
