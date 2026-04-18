# frozen_string_literal: true

RSpec.describe "OSC handlers and DEC private modes" do
  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }

  it "updates OSC dynamic colors" do
    terminal.write("\e]10;#eeeeee\a")
    terminal.write("\e]11;#111111\a")
    terminal.write("\e]12;#00ff00\a")

    colors = terminal.internal.input_handler.color_manager
    expect(colors.foreground).to eq("#eeeeee")
    expect(colors.background).to eq("#111111")
    expect(colors.cursor).to eq("#00ff00")
  end

  it "updates and resets OSC palette colors" do
    terminal.write("\e]4;1;#ff1111\a")
    colors = terminal.internal.input_handler.color_manager
    expect(colors.palette[1]).to eq("#ff1111")

    terminal.write("\e]104;1\a")
    expect(colors.palette[1]).to eq(RTerm::Theme.new.red)
  end

  it "emits hyperlink and clipboard events" do
    hyperlink = nil
    clipboard = nil
    terminal.on(:hyperlink) { |payload| hyperlink = payload }
    terminal.on(:clipboard) { |payload| clipboard = payload }

    terminal.write("\e]8;id=1;https://example.com\a")
    terminal.write("\e]52;c;SGVsbG8=\a")

    expect(hyperlink).to eq({ params: "id=1", uri: "https://example.com" })
    expect(clipboard).to eq({ selection: "c", data: "SGVsbG8=" })
  end

  it "tracks mouse and focus modes" do
    terminal.write("\e[?1000h\e[?1006h\e[?1004h")

    expect(terminal.modes[:mouse_tracking_mode]).to eq(:x10)
    expect(terminal.modes[:sgr_mouse_mode]).to be true
    expect(terminal.modes[:focus_event_mode]).to be true

    terminal.write("\e[?1000l\e[?1006l\e[?1004l")

    expect(terminal.modes[:mouse_tracking_mode]).to be_nil
    expect(terminal.modes[:sgr_mouse_mode]).to be false
    expect(terminal.modes[:focus_event_mode]).to be false
  end
end
