# frozen_string_literal: true

RSpec.describe "specification compatibility APIs" do
  it "exposes CircularList#is_full? as an alias" do
    list = RTerm::Common::CircularList.new(1)
    list.push(:item)

    expect(list).to be_is_full
  end

  it "returns wrapped ranges for buffer rows" do
    buffer = RTerm::Common::Buffer.new(5, 3)
    buffer.get_line(0).is_wrapped = true
    buffer.get_line(1).is_wrapped = true

    expect(buffer.get_wrapped_range_for_line(1)).to eq(0..2)
  end

  it "exposes non-predicate cell attribute readers" do
    cell = RTerm::Common::CellData.new
    cell.bold = true
    cell.italic = true
    cell.underline = true

    expect(cell.bold).to be true
    expect(cell.italic).to be true
    expect(cell.underline).to be true
  end

  it "allows parser namespace print and execute handlers" do
    terminal = RTerm::Terminal.new
    printed = nil
    bell = false

    terminal.parser.set_print_handler { |data| printed = data }
    terminal.parser.set_execute_handler(0x07) { bell = true }
    terminal.write("x\a")

    expect(printed).to eq("x")
    expect(bell).to be true
  end
end
