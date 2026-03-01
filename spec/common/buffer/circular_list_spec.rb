# frozen_string_literal: true

RSpec.describe RTerm::Common::CircularList do
  describe "#push and #[]" do
    it "stores and retrieves elements" do
      list = described_class.new(5)
      list.push("a")
      list.push("b")
      expect(list[0]).to eq("a")
      expect(list[1]).to eq("b")
    end

    it "discards the oldest element when max_length is exceeded" do
      list = described_class.new(3)
      list.push("a")
      list.push("b")
      list.push("c")
      list.push("d")
      expect(list.length).to eq(3)
      expect(list[0]).to eq("b")
      expect(list[1]).to eq("c")
      expect(list[2]).to eq("d")
    end

    it "returns nil for out-of-bounds index" do
      list = described_class.new(5)
      list.push("a")
      expect(list[-1]).to be_nil
      expect(list[1]).to be_nil
    end
  end

  describe "#[]=" do
    it "sets an element at the given index" do
      list = described_class.new(5)
      list.push("a")
      list.push("b")
      list[1] = "c"
      expect(list[1]).to eq("c")
    end

    it "does nothing for out-of-bounds index" do
      list = described_class.new(5)
      list.push("a")
      list[5] = "x"
      expect(list.length).to eq(1)
    end
  end

  describe "#pop" do
    it "removes and returns the last element" do
      list = described_class.new(5)
      list.push("a")
      list.push("b")
      expect(list.pop).to eq("b")
      expect(list.length).to eq(1)
    end

    it "returns nil when empty" do
      list = described_class.new(5)
      expect(list.pop).to be_nil
    end
  end

  describe "#length" do
    it "starts at 0" do
      list = described_class.new(5)
      expect(list.length).to eq(0)
    end

    it "tracks the current number of elements" do
      list = described_class.new(5)
      list.push("a")
      list.push("b")
      expect(list.length).to eq(2)
    end
  end

  describe "#max_length=" do
    it "keeps data when increasing max_length" do
      list = described_class.new(3)
      list.push("a")
      list.push("b")
      list.max_length = 5
      expect(list.length).to eq(2)
      expect(list[0]).to eq("a")
      expect(list[1]).to eq("b")
    end

    it "truncates oldest elements when decreasing max_length" do
      list = described_class.new(5)
      list.push("a")
      list.push("b")
      list.push("c")
      list.push("d")
      list.max_length = 2
      expect(list.length).to eq(2)
      expect(list[0]).to eq("c")
      expect(list[1]).to eq("d")
    end
  end

  describe "#splice" do
    it "deletes elements at the given position" do
      list = described_class.new(5)
      %w[a b c d].each { |v| list.push(v) }
      list.splice(1, 2)
      expect(list.length).to eq(2)
      expect(list[0]).to eq("a")
      expect(list[1]).to eq("d")
    end

    it "inserts elements at the given position" do
      list = described_class.new(10)
      %w[a b c].each { |v| list.push(v) }
      list.splice(1, 0, "x", "y")
      expect(list.length).to eq(5)
      expect(list.to_a).to eq(%w[a x y b c])
    end

    it "replaces elements at the given position" do
      list = described_class.new(10)
      %w[a b c d].each { |v| list.push(v) }
      list.splice(1, 2, "x")
      expect(list.length).to eq(3)
      expect(list.to_a).to eq(%w[a x d])
    end
  end

  describe "#trim_start" do
    it "removes elements from the beginning" do
      list = described_class.new(5)
      %w[a b c d].each { |v| list.push(v) }
      list.trim_start(2)
      expect(list.length).to eq(2)
      expect(list[0]).to eq("c")
      expect(list[1]).to eq("d")
    end

    it "handles count greater than length" do
      list = described_class.new(5)
      list.push("a")
      list.trim_start(10)
      expect(list.length).to eq(0)
    end

    it "does nothing for count <= 0" do
      list = described_class.new(5)
      list.push("a")
      list.trim_start(0)
      expect(list.length).to eq(1)
    end
  end

  describe "#shift_elements" do
    it "shifts elements to the right" do
      list = described_class.new(10)
      %w[a b c d e].each { |v| list.push(v) }
      list.shift_elements(1, 2, 2)
      expect(list[3]).to eq("b")
      expect(list[4]).to eq("c")
    end

    it "shifts elements to the left" do
      list = described_class.new(10)
      %w[a b c d e].each { |v| list.push(v) }
      list.shift_elements(2, 2, -1)
      expect(list[1]).to eq("c")
      expect(list[2]).to eq("d")
    end

    it "does nothing when offset is 0" do
      list = described_class.new(5)
      %w[a b c].each { |v| list.push(v) }
      list.shift_elements(0, 3, 0)
      expect(list.to_a).to eq(%w[a b c])
    end
  end

  describe "#each" do
    it "yields each element in order" do
      list = described_class.new(5)
      %w[a b c].each { |v| list.push(v) }
      expect(list.to_a).to eq(%w[a b c])
    end

    it "returns an Enumerator when no block is given" do
      list = described_class.new(5)
      expect(list.each).to be_an(Enumerator)
    end

    it "works correctly after wrap-around" do
      list = described_class.new(3)
      %w[a b c d e].each { |v| list.push(v) }
      expect(list.to_a).to eq(%w[c d e])
    end
  end

  describe "#clear" do
    it "removes all elements" do
      list = described_class.new(5)
      %w[a b c].each { |v| list.push(v) }
      list.clear
      expect(list.length).to eq(0)
      expect(list[0]).to be_nil
    end
  end

  describe "#full?" do
    it "returns false when not at capacity" do
      list = described_class.new(5)
      list.push("a")
      expect(list.full?).to be false
    end

    it "returns true when at capacity" do
      list = described_class.new(2)
      list.push("a")
      list.push("b")
      expect(list.full?).to be true
    end
  end
end
