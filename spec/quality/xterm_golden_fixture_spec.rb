# frozen_string_literal: true

require "yaml"

RSpec.describe "xterm golden fixture comparison" do
  fixtures = YAML.load_file(File.expand_path("../fixtures/xterm_golden_sequences.yml", __dir__))

  fixtures.each do |fixture|
    it "matches #{fixture.fetch('name')}" do
      terminal = RTerm::Terminal.new(cols: fixture.fetch("cols"), rows: fixture.fetch("rows"))
      terminal.write(fixture.fetch("input"))

      Array(fixture["lines"]).each_with_index do |expected, row|
        expect(terminal.buffer.active.get_line(row).to_string).to include(expected)
      end

      Array(fixture["cells"]).each do |cell_fixture|
        cell = terminal.buffer.active.get_line(cell_fixture.fetch("row")).get_cell(cell_fixture.fetch("col"))
        expect(cell.fg_color_mode.to_s).to eq(cell_fixture.fetch("fg_color_mode"))
        expect(cell.fg_color).to eq(cell_fixture.fetch("fg_color"))
      end

      Array(fixture["links"]).each do |link_fixture|
        cell = terminal.buffer.active.get_line(link_fixture.fetch("row")).get_cell(link_fixture.fetch("col"))
        expect(cell.link[:uri]).to eq(link_fixture.fetch("uri"))
      end
    end
  end
end
