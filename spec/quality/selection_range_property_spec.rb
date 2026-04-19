# frozen_string_literal: true

RSpec.describe "selection range properties" do
  it "keeps linear and rectangular selections bounded for mixed-width rows" do
    terminal = RTerm::Terminal.new(cols: 12, rows: 4)
    terminal.write("a漢b🙂c\r\ndefghi")

    (0...terminal.rows).each do |row|
      (0...terminal.cols).each do |col|
        terminal.select(col, row, 3)
        expect(terminal.selection).to be_a(String)

        terminal.select_rectangle(col, row, col + 1, row)
        expect(terminal.selection).to be_a(String)
      end
    end
  end
end
