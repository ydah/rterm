# frozen_string_literal: true

RSpec.describe "DCS and OSC enhanced handling" do
  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }

  it "stores OSC 8 hyperlink metadata on printed cells" do
    terminal.write("\e]8;id=doc;https://example.com\aLink\e]8;;\a plain")

    linked = terminal.buffer.active.get_line(0).get_cell(0)
    plain = terminal.buffer.active.get_line(0).get_cell(5)

    expect(linked.link).to eq({ params: "id=doc", uri: "https://example.com" })
    expect(plain.link).to be_nil
  end

  it "responds to DECRQSS DCS requests" do
    response = nil
    terminal.on(:data) { |data| response = data }

    terminal.write("\eP$qm\e\\")

    expect(response).to eq("\eP1$r0m\e\\")
  end

  it "emits Sixel image payloads" do
    image = nil
    terminal.on(:image) { |payload| image = payload }

    terminal.write("\ePqABCDEF\e\\")

    expect(image).to eq({ protocol: :sixel, params: [], data: "ABCDEF" })
  end

  it "emits iTerm2 image payloads" do
    image = nil
    terminal.on(:image) { |payload| image = payload }

    terminal.write("\e]1337;File=name=test.png;inline=1:AAAA\a")

    expect(image).to eq({ protocol: :iterm2, params: "name=test.png;inline=1", data: "AAAA" })
  end
end
