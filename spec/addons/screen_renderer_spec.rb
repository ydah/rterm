# frozen_string_literal: true

RSpec.describe RTerm::Addon::ScreenRenderer do
  it "renders visible rows into a headless element tree" do
    terminal = RTerm::Terminal.new(cols: 5, rows: 2)
    renderer = described_class.new
    screens = []

    renderer.onScreen { |payload| screens << payload }
    terminal.load_addon(renderer)
    terminal.write("hi")

    expect(renderer).to be_active
    expect(renderer.rendererType).to eq(:screen)
    expect(renderer.elements).to be_a(RTerm::Terminal::HostElement)
    expect(renderer.elements.children.length).to eq(2)
    expect(renderer.rows.first).to include(row: 0, text: "hi   ")
    expect(renderer.rows.first[:cells].first).to include(row: 0, col: 0, char: "h", width: 1)
    expect(renderer.text).to start_with("hi")
    expect(screens.last).to include(type: :screen)
  end

  it "exposes an accessibility tree with cursor state" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2, screen_reader_mode: true)
    renderer = described_class.new

    terminal.open
    terminal.load_addon(renderer)
    terminal.write("ok")

    tree = renderer.accessibilityTree
    expect(tree).to include(role: "terminal", cols: 4, rows: 2)
    expect(tree[:children].first).to include(role: "row", row: 0, text: "ok  ")
    expect(tree[:cursor]).to include(row: 0, col: 2)
    expect(tree[:live_region]).to include(text_content: "ok")
  end

  it "renders into a supplied host and refreshes on terminal render events" do
    terminal = RTerm::Terminal.new(cols: 3, rows: 1)
    host = RTerm::Terminal::HostElement.new(class_name: "host")
    renderer = described_class.new(host: host)

    terminal.load_addon(renderer)
    terminal.write("abc")

    expect(renderer.host).to equal(host)
    expect(host.children.length).to eq(1)
    expect(host.children.first.children.length).to eq(3)
    expect(host.children.first.textContent).to eq("abc")
  end

  it "annotates rendered link cells" do
    terminal = RTerm::Terminal.new(cols: 28, rows: 1)
    renderer = described_class.new

    terminal.load_addon(renderer)
    terminal.write("open https://example.com")

    link_cells = renderer.rows.first[:cells].select { |cell| cell[:link] }

    expect(link_cells.first[:link]).to include(uri: "https://example.com")
    expect(link_cells.map { |cell| cell[:col] }).to include(5, 23)
  end
end
