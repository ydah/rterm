# frozen_string_literal: true

RSpec.describe RTerm::Addon::Search do
  let(:terminal) { RTerm::Terminal.new(cols: 80, rows: 24) }
  let(:search) { described_class.new }

  before do
    terminal.load_addon(search)
  end

  describe "#find_all" do
    it "finds all occurrences of a string" do
      terminal.write("hello world hello\r\n")
      terminal.write("hello again\r\n")
      matches = search.find_all("hello")
      expect(matches.length).to eq(3)
    end

    it "finds with case insensitive by default" do
      terminal.write("Hello HELLO hello\r\n")
      matches = search.find_all("hello")
      expect(matches.length).to eq(3)
    end

    it "supports case sensitive search" do
      terminal.write("Hello HELLO hello\r\n")
      matches = search.find_all("hello", case_sensitive: true)
      expect(matches.length).to eq(1)
    end

    it "supports regex search" do
      terminal.write("foo123 bar456\r\n")
      matches = search.find_all("\\d+", regex: true)
      expect(matches.length).to eq(2)
    end

    it "supports whole word search" do
      terminal.write("hello helloworld hello\r\n")
      matches = search.find_all("hello", whole_word: true)
      expect(matches.length).to eq(2)
    end

    it "returns empty array when no matches" do
      terminal.write("hello world\r\n")
      matches = search.find_all("xyz")
      expect(matches).to be_empty
    end

    it "finds matches across wrapped rows" do
      wrapped_terminal = RTerm::Terminal.new(cols: 5, rows: 4)
      wrapped_search = described_class.new
      wrapped_terminal.load_addon(wrapped_search)

      wrapped_terminal.write("helloworld")
      matches = wrapped_search.find_all("lowo")

      expect(matches.first).to include(row: 0, col: 3, length: 4, text: "lowo")
      expect(matches.first[:ranges]).to eq(
        [
          { row: 0, line_index: 0, col: 3, length: 2 },
          { row: 1, line_index: 1, col: 0, length: 2 }
        ]
      )
    end

    it "reports wide character matches using cell widths" do
      terminal.write("a漢b")

      match = search.find_all("漢b").first

      expect(match).to include(row: 0, col: 1, length: 3, text: "漢b")
      expect(match[:ranges]).to eq([{ row: 0, line_index: 0, col: 1, length: 3 }])
    end

    it "can include retained scrollback" do
      small = RTerm::Terminal.new(cols: 10, rows: 2, scrollback: 5)
      small_search = described_class.new
      small.load_addon(small_search)
      small.write("one\r\ntwo\r\nthree\r\nfour")

      visible_matches = small_search.find_all("one")
      scrollback_matches = small_search.find_all("one", scrollback: true)

      expect(visible_matches).to be_empty
      expect(scrollback_matches.first).to include(row: 0, line_index: 0, col: 0, length: 3)
    end

    it "stores decorations when requested" do
      terminal.write("hello hello")

      matches = search.find_all("hello", decorations: { background: "#ffff00" })

      expect(matches.length).to eq(2)
      expect(search.decorations.map { |item| item[:decoration] }).to all(eq({ background: "#ffff00" }))
    end

    it "returns empty matches for invalid regular expressions" do
      terminal.write("hello")

      expect(search.find_all("[", regex: true)).to eq([])
    end
  end

  describe "#find_next" do
    it "finds the next match" do
      terminal.write("aaa bbb aaa\r\n")
      match = search.find_next("aaa")
      expect(match).not_to be_nil
      expect(match[:col]).to eq(0)
    end

    it "wraps around" do
      terminal.write("aaa bbb aaa\r\n")
      search.find_next("aaa") # first
      search.find_next("aaa") # second
      match = search.find_next("aaa") # wraps to first
      expect(match[:col]).to eq(0)
    end

    it "resets current match when the query changes" do
      terminal.write("aaa bbb aaa\r\n")
      search.find_next("aaa")

      match = search.find_next("bbb")

      expect(match[:col]).to eq(4)
    end

    it "returns nil when no match" do
      terminal.write("hello\r\n")
      expect(search.find_next("xyz")).to be_nil
    end
  end

  describe "#find_previous" do
    it "finds the previous match" do
      terminal.write("aaa bbb aaa\r\n")
      match = search.find_previous("aaa")
      expect(match).not_to be_nil
    end
  end
end
