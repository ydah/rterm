# frozen_string_literal: true

RSpec.describe "parser fuzz smoke tests" do
  it "does not raise for deterministic mixed control streams" do
    random = Random.new(12_345)
    fragments = [
      "plain",
      "\e[31m",
      "\e[0m",
      "\e[2J",
      "\e[?1049h",
      "\e[?1049l",
      "\e]2;title\a",
      "\ePqABC\e\\",
      "\r\n",
      "漢🙂"
    ]
    terminal = RTerm::Terminal.new(cols: 40, rows: 10)

    200.times do
      stream = Array.new(20) { fragments[random.rand(fragments.length)] }.join
      expect { terminal.write(stream) }.not_to raise_error
      expect(terminal.buffer.active.x).to be_between(0, terminal.cols - 1)
      expect(terminal.buffer.active.y).to be_between(0, terminal.rows - 1)
    end
  end
end
