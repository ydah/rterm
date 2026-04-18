# frozen_string_literal: true

RSpec.describe "terminal option behavior" do
  it "converts LF to CRLF when convert_eol is enabled" do
    terminal = RTerm::Terminal.new(cols: 10, rows: 3, convert_eol: true)

    terminal.write("a\nb")

    expect(terminal.buffer.active.get_line(0).to_string).to eq("a")
    expect(terminal.buffer.active.get_line(1).to_string).to eq("b")
  end

  it "does not emit input when stdin is disabled" do
    terminal = RTerm::Terminal.new(disable_stdin: true)
    received = nil
    terminal.on(:data) { |data| received = data }

    terminal.input("ignored")

    expect(received).to be_nil
  end
end
