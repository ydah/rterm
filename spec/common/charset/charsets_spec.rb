# frozen_string_literal: true

RSpec.describe RTerm::Common::Charsets do
  it "maps DEC special graphics characters" do
    charset = described_class.fetch(:dec_special_graphics)

    expect(charset.translate("q")).to eq("─")
    expect(charset.translate("x")).to eq("│")
    expect(charset.translate("m")).to eq("└")
  end

  it "falls back to identity for unknown characters and charsets" do
    expect(described_class.fetch(:ascii).translate("A")).to eq("A")
    expect(described_class.fetch(:missing).translate("A")).to eq("A")
  end
end

RSpec.describe "charset escape sequences" do
  it "uses DEC special graphics after ESC ( 0 and returns to ASCII after ESC ( B" do
    terminal = RTerm::Terminal.new(cols: 10, rows: 2)

    terminal.write("\e(0qxm\e(Bq")

    expect(terminal.buffer.active.get_line(0).to_string).to eq("─│└q")
  end
end
