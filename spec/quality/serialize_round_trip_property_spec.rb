# frozen_string_literal: true

RSpec.describe "serialize round-trip properties" do
  it "replays representative ANSI snapshots to equivalent visible text" do
    samples = [
      "plain text",
      "\e[31mred\e[0m normal",
      "wide 漢🙂 text",
      "line1\r\nline2",
      "\e]8;id=1;https://example.com\aLink\e]8;;\a"
    ]

    samples.each do |sample|
      original = RTerm::Terminal.new(cols: 40, rows: 5)
      serializer = RTerm::Addon::Serialize.new
      original.load_addon(serializer)
      original.write(sample)

      replayed = RTerm::Terminal.new(cols: 40, rows: 5)
      replayed.write(serializer.serialize)

      expect(replayed.buffer.active.get_line(0).to_string).to eq(original.buffer.active.get_line(0).to_string)
    end
  end

  it "restores structured snapshots without changing visible text" do
    original = RTerm::Terminal.new(cols: 40, rows: 5)
    serializer = RTerm::Addon::Serialize.new
    original.load_addon(serializer)
    original.write("one\r\ntwo\r\nthree")
    snapshot = serializer.snapshot(scrollback: 3)

    restored = RTerm::Terminal.new(cols: 10, rows: 2)
    restored_serializer = RTerm::Addon::Serialize.new
    restored.load_addon(restored_serializer)
    restored_serializer.restore(snapshot)

    expect(restored.buffer.active.get_line(0).to_string).to eq(original.buffer.active.get_line(0).to_string)
  end
end
