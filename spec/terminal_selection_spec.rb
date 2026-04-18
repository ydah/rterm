# frozen_string_literal: true

RSpec.describe "terminal selection API" do
  let(:terminal) { RTerm::Terminal.new(cols: 10, rows: 3) }

  it "selects text within a single line" do
    terminal.write("hello world")

    terminal.select(1, 0, 4)

    expect(terminal.selection).to eq("ello")
  end

  it "selects text across visible lines" do
    terminal.write("abcdef\r\nghijkl")

    terminal.select(4, 0, 4)

    expect(terminal.selection).to eq("ef\r\ngh")
  end

  it "selects all visible text and clears selection" do
    terminal.write("one\r\ntwo")

    terminal.select_all
    expect(terminal.selection).to eq("one\r\ntwo")

    terminal.clear_selection
    expect(terminal.selection).to eq("")
  end
end
