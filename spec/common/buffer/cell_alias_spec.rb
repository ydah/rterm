# frozen_string_literal: true

RSpec.describe RTerm::Common::Cell do
  it "is a cell data class matching the specification name" do
    cell = described_class.new
    cell.char = "x"
    cell.bold = true

    expect(cell).to be_a(RTerm::Common::CellData)
    expect(cell.char).to eq("x")
    expect(cell).to be_bold
  end
end
