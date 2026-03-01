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
