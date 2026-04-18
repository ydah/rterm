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

  it "selects wide characters by cell columns" do
    terminal.write("a漢b")

    terminal.select(1, 0, 2)

    expect(terminal.selection).to eq("漢")
  end

  it "does not insert line breaks across soft-wrapped rows" do
    wrapped = RTerm::Terminal.new(cols: 5, rows: 3)
    wrapped.write("helloworld")

    wrapped.select(3, 0, 4)

    expect(wrapped.selection).to eq("lowo")
  end

  it "selects all retained scrollback text" do
    scrolled = RTerm::Terminal.new(cols: 10, rows: 2, scrollback: 5)
    scrolled.write("one\r\ntwo\r\nthree\r\nfour")

    scrolled.select_all

    expect(scrolled.selection).to include("one\r\ntwo\r\nthree\r\nfour")
  end

  it "selects words using the configured separator set" do
    terminal.write("abc def")

    terminal.select_word(5, 0)

    expect(terminal.selection).to eq("def")
  end

  it "selects rectangular cell ranges" do
    terminal.write("abcd\r\nefgh")

    terminal.select_rectangle(1, 0, 2, 1)

    expect(terminal.selection).to eq("bc\r\nfg")
  end
end
