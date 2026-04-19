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

  it "responds to OSC dynamic color queries" do
    responses = []
    terminal.on(:data) { |data| responses << data }
    terminal.write("\e]10;#112233\a")
    terminal.write("\e]11;#445566\a")
    terminal.write("\e]12;#778899\a")

    terminal.write("\e]10;?\a")
    terminal.write("\e]11;?\a")
    terminal.write("\e]12;?\a")

    expect(responses).to eq(
      [
        "\e]10;rgb:1111/2222/3333\a",
        "\e]11;rgb:4444/5555/6666\a",
        "\e]12;rgb:7777/8888/9999\a"
      ]
    )
  end

  it "updates and resets OSC palette colors" do
    terminal.write("\e]4;1;#ff1111\a")
    colors = terminal.internal.input_handler.color_manager
    expect(colors.palette[1]).to eq("#ff1111")

    terminal.write("\e]104;1\a")
    expect(colors.palette[1]).to eq(RTerm::Theme.new.red)
  end

  it "responds to OSC palette color queries" do
    responses = []
    terminal.on(:data) { |data| responses << data }
    terminal.write("\e]4;1;#ff1111\a")

    terminal.write("\e]4;1;?\a")

    expect(responses).to eq(["\e]4;1;rgb:ffff/1111/1111\a"])
  end

  it "emits hyperlink and clipboard events" do
    hyperlink = nil
    clipboard = nil
    terminal.on(:hyperlink) { |payload| hyperlink = payload }
    terminal.on(:clipboard) { |payload| clipboard = payload }

    terminal.write("\e]8;id=1;https://example.com\a")
    terminal.write("\e]52;c;SGVsbG8=\a")

    expect(hyperlink).to eq({ params: "id=1", uri: "https://example.com" })
    expect(clipboard).to include(selection: "c", data: "SGVsbG8=", decoded: "Hello")
  end

  it "responds to OSC 52 clipboard queries from stored data" do
    responses = []
    requests = []
    terminal.on(:data) { |data| responses << data }
    terminal.on(:clipboard_request) { |payload| requests << payload }
    terminal.write("\e]52;c;SGVsbG8=\a")

    terminal.write("\e]52;c;?\a")

    expect(requests).to eq([{ selection: "c" }])
    expect(responses).to eq(["\e]52;c;SGVsbG8=\a"])
  end

  it "emits nil decoded clipboard data for invalid OSC 52 base64" do
    clipboard = nil
    terminal.on(:clipboard) { |payload| clipboard = payload }

    terminal.write("\e]52;c;not-base64\a")

    expect(clipboard).to include(selection: "c", data: "not-base64", decoded: nil)
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
