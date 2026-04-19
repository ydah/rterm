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

  it "responds to DECRQSS cursor style requests" do
    response = nil
    terminal.on(:data) { |data| response = data }
    terminal.write("\e[5 q")

    terminal.write("\eP$q q\e\\")

    expect(response).to eq("\eP1$r5 q\e\\")
  end

  it "responds to DECRQSS DECSCA requests" do
    response = nil
    terminal.on(:data) { |data| response = data }
    terminal.write("\e[1\"q")

    terminal.write("\eP$q\"q\e\\")

    expect(response).to eq("\eP1$r1\"q\e\\")
  end

  it "responds to DECRQSS DECSLRM requests" do
    response = nil
    terminal.on(:data) { |data| response = data }
    terminal.write("\e[?69h\e[3;8s")

    terminal.write("\eP$qs\e\\")

    expect(response).to eq("\eP1$r3;8s\e\\")
  end

  it "emits Sixel image payloads" do
    image = nil
    terminal.on(:image) { |payload| image = payload }

    terminal.write("\ePqABCDEF\e\\")

    expect(image).to include(
      protocol: :sixel,
      params: [],
      data: "ABCDEF",
      geometry: { cell_width: 6, pixel_height: 6 },
      placement: { buffer: :normal, row: 0, col: 0 },
      raw_sequence: "\ePqABCDEF\e\\"
    )
    expect(terminal.images).to include(image)
  end

  it "emits iTerm2 image payloads" do
    image = nil
    terminal.on(:image) { |payload| image = payload }

    terminal.write("\e]1337;File=name=test.png;inline=1:AAAA\a")

    expect(image).to include(
      protocol: :iterm2,
      params: "name=test.png;inline=1",
      attributes: { "name" => "test.png", "inline" => "1" },
      data: "AAAA",
      placement: { buffer: :normal, row: 0, col: 0 },
      raw_sequence: "\e]1337;File=name=test.png;inline=1:AAAA\a"
    )
  end
end
