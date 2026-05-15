# frozen_string_literal: true

RSpec.describe RTerm::Addon::HostIntegration do
  it "mounts a host surface and forwards terminal events as commands" do
    terminal = RTerm::Terminal.new(cols: 6, rows: 2, screenReaderMode: true)
    delivered = []
    addon = described_class.new(transport: ->(command) { delivered << command })

    terminal.load_addon(addon)
    addon.mount(focus: true)
    terminal.write("hi")
    terminal.copy("clip")

    expect(addon).to be_active
    expect(delivered.map { |command| command[:type] }).to include(
      :activate,
      :mount,
      :focus,
      :render,
      :screen_reader,
      :accessibility,
      :clipboard_write
    )
    mount = delivered.find { |command| command[:type] == :mount }
    expect(mount[:payload]).to include(cols: 6, rows: 2)
    expect(mount[:payload][:textarea]).to include(tag_name: "textarea", focused: false)
    expect(mount[:payload][:accessibility]).to include(screen_reader_mode: true)
    render = delivered.reverse.find { |command| command[:type] == :render }
    expect(render[:payload]).to include(start: 0, end: 1)
    expect(render[:payload][:accessibility_tree]).to include(cols: 6, rows: 2)
  end

  it "receives host input, keyboard, pointer, and composition events" do
    terminal = RTerm::Terminal.new(cols: 8, rows: 3)
    addon = described_class.new
    input = []
    composition = []

    terminal.on(:data) { |payload| input << payload }
    terminal.onCompositionEnd { |payload| composition << payload }
    terminal.load_addon(addon)

    addon.receive(type: :input, data: "ls\r")
    addon.receive(type: :key, key: "a", text: "a")
    addon.receive(type: :paste, data: "pasted")
    addon.receive(type: :compositionEnd, data: "kana")

    terminal.write("\e[?1000h")
    addon.receive(type: :mouse, button: :left, col: 0, row: 0)

    expect(input).to include("ls\r", "a", "pasted", "kana", "\e[M !!")
    expect(composition.last).to include(data: "kana", committed: true)
  end

  it "receives host selection and copy events" do
    terminal = RTerm::Terminal.new(cols: 8, rows: 3)
    addon = described_class.new
    clipboard = []

    terminal.on(:clipboard) { |payload| clipboard << payload }
    terminal.load_addon(addon)
    terminal.write("abcdef\r\nghijkl")

    addon.receive(type: :selection, mode: :linear, startCol: 2, startRow: 0, endCol: 1, endRow: 1)
    expect(terminal.selection).to eq("cdef\r\ngh")

    addon.receive(type: :selection, mode: :rectangle, startCol: 1, startRow: 0, endCol: 2, endRow: 1)
    expect(terminal.selection).to eq("bc\r\nhi")

    addon.receive(type: :copy)
    expect(clipboard.last).to include(decoded: "bc\r\nhi", allowed: true)

    addon.receive(type: :clearSelection)
    expect(terminal.selection).to eq("")
  end

  it "applies host resize and cell measurements" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2)
    addon = described_class.new
    terminal.load_addon(addon)

    addon.receive(type: :resize, cols: 20, rows: 5, cellWidth: 10.5, cellHeight: 21)

    service = terminal.internal.services.get(RTerm::Services::CHAR_SIZE_SERVICE)
    expect(terminal.cols).to eq(20)
    expect(terminal.rows).to eq(5)
    expect(service.size).to eq(width: 10.5, height: 21, source: :measured)
    expect(addon.commands.map { |command| command[:type] }).to include(:font_measure, :resize)
  end

  it "fulfills asynchronous clipboard read requests from the host" do
    terminal = RTerm::Terminal.new
    addon = described_class.new
    output = []

    terminal.on(:data) { |payload| output << payload }
    terminal.load_addon(addon)

    terminal.write("\e]52;c;?\a")
    expect(addon.pendingClipboardRequests.length).to eq(1)
    expect(addon.commands.map { |command| command[:type] }).to include(:clipboard_read_request)

    addon.receive(type: :clipboardText, selection: "c", text: "from host")

    expect(addon.clipboardStore["clipboard"]).to eq("from host")
    expect(output.last).to eq("\e]52;c;ZnJvbSBob3N0\a")
    expect(addon.pendingClipboardRequests).to be_empty
    expect(addon.commands.map { |command| command[:type] }).to include(:clipboard_response)
  end

  it "forwards renderer and font lifecycle events" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2)
    addon = described_class.new
    terminal.load_addon(addon)

    screen = RTerm::Addon::ScreenRenderer.new
    fonts = RTerm::Addon::WebFonts.new(false)
    renderer = RTerm::Addon::WebGL.new

    terminal.load_addon(screen)
    terminal.load_addon(fonts)
    terminal.load_addon(renderer)

    fonts.registerFont("JetBrains Mono", "url('/fonts/jetbrains.woff2')")
    fonts.loadFonts("JetBrains Mono")
    renderer.attachHost(:canvas, viewport: { cellWidth: 9, cellHeight: 18 })
    terminal.write("ok")

    types = addon.commands.map { |command| command[:type] }
    expect(types).to include(:font_load, :renderer_change, :screen, :render)
  end
end
