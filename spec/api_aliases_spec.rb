# frozen_string_literal: true

RSpec.describe "specification APIs" do
  it "exposes CircularList#is_full? as an alias" do
    list = RTerm::Common::CircularList.new(1)
    list.push(:item)

    expect(list).to be_is_full
  end

  it "returns wrapped ranges for buffer rows" do
    buffer = RTerm::Common::Buffer.new(5, 3)
    buffer.get_line(0).is_wrapped = true
    buffer.get_line(1).is_wrapped = true

    expect(buffer.get_wrapped_range_for_line(1)).to eq(0..2)
  end

  it "supports buffer camelCase aliases" do
    buffer = RTerm::Common::Buffer.new(4, 3, 10)
    line = buffer.getLine(0)

    first = RTerm::Common::CellData.new
    second = RTerm::Common::CellData.new
    third = RTerm::Common::CellData.new
    first.char = "a"
    second.char = "b"
    third.char = "c"
    line.setCell(0, first)
    line.setCell(1, second)
    line.setCell(2, third)

    expect(line).to be_a(RTerm::Common::BufferLine)
    expect(buffer.getLine(0)).to eq(buffer.get_line(0))
    expect(buffer.baseY).to eq(0)
    expect(buffer.yBase).to eq(0)
    expect(buffer.yDisp).to eq(0)
    expect(buffer.cursorX).to eq(0)
    expect(buffer.cursorY).to eq(0)
    expect(buffer.scrollTop).to eq(0)
    expect(buffer.scrollBottom).to eq(2)
    expect(buffer.get_wrapped_range_for_line(0)).to eq(0..0)
    expect(buffer.getWrappedRangeForLine(0)).to eq(0..0)
    expect(buffer.translateBufferLineToString(0)).to eq("abc")

    buffer.baseY = 1
    buffer.cursorX = 1
    buffer.cursorY = 2
    expect(buffer.y_base).to eq(1)
    expect(buffer.x).to eq(1)
    expect(buffer.y).to eq(2)
  end

  it "supports buffer line camelCase aliases" do
    line = RTerm::Common::BufferLine.new(4)
    first = RTerm::Common::CellData.new
    second = RTerm::Common::CellData.new
    third = RTerm::Common::CellData.new
    first.char = "a"
    second.char = "b"
    third.char = "c"

    line.setCell(0, first)
    line.setCell(1, second)
    line.setCell(2, third)

    expect(line.getCell(1).char).to eq("b")
    expect(line.getLength).to eq(4)
    expect(line.getTrimmedLength).to eq(3)
    expect(line.translateToString).to eq("abc")
    expect(line.toString).to eq("abc")

    line.insertCells(1, 1, RTerm::Common::CellData.new.tap(&:reset))
    expect(line.getTrimmedLength).to eq(4)
    expect(line.getCell(1).char).to eq("")
  end

  it "exposes non-predicate cell attribute readers" do
    cell = RTerm::Common::CellData.new
    cell.bold = true
    cell.italic = true
    cell.underline = true

    expect(cell.bold).to be true
    expect(cell.italic).to be true
    expect(cell.underline).to be true
  end

  it "allows parser namespace print and execute handlers" do
    terminal = RTerm::Terminal.new
    printed = nil
    bell = false

    terminal.parser.set_print_handler { |data| printed = data }
    terminal.parser.set_execute_handler(0x07) { bell = true }
    terminal.write("x\a")

    expect(printed).to eq("x")
    expect(bell).to be true
  end

  it "supports parser handler camelCase aliases" do
    terminal = RTerm::Terminal.new
    csi_called = false

    expect(terminal.parser).to respond_to(:setCsiHandler)
    expect(terminal.parser).to respond_to(:setOscHandler)
    expect(terminal.parser).to respond_to(:setPrintHandler)
    expect(terminal.parser).to respond_to(:setExecuteHandler)

    terminal.parser.setCsiHandler({ final: "z" }) { csi_called = true }
    terminal.write("\e[1z")

    expect(csi_called).to be true
  end

  it "provides selection APIs" do
    terminal = RTerm::Terminal.new
    terminal.write("hello world")

    terminal.select(0, 0, 5)

    expect(terminal.getSelection).to eq("hello")
    expect(terminal.hasSelection).to be true

    terminal.clearSelection

    expect(terminal.getSelection).to eq("")
    expect(terminal.hasSelection).to be false
  end

  it "provides scroll and viewport APIs" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2, scrollback: 20)
    10.times { |i| terminal.writeln("line #{i}") }

    active = terminal.internal.buffer_set.active
    terminal.scrollToBottom
    expect(active.y_disp).to eq(active.y_base)

    terminal.scrollToTop
    expect(active.y_disp).to eq(0)

    terminal.scrollToLine(2)
    expect(active.y_disp).to eq(2)

    terminal.scrollLines(-1)
    expect(active.y_disp).to eq(1)

    terminal.scrollPages(1)
    expect(active.y_disp).to eq(3)
  end

  it "supports setOption/getOption with snake and camelCase names" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 3, scrollback: 5, cursor_blink: false, cursor_style: :block)
    terminal.write("x")

    terminal.setOption(:cursor_blink, true)
    terminal.setOption("cursorStyle", :underline)
    expect(terminal.getOption("cursorBlink")).to be true
    expect(terminal.getOption("cursor_style")).to eq(:underline)
    expect(terminal.cursor_info).to include(style: :underline, blink: true)

    terminal.setOption("cols", 8)
    expect(terminal.cols).to eq(8)
    expect(terminal.getOption(:cols)).to eq(8)
    expect(terminal.getOption("rows")).to eq(3)
    expect { terminal.setOption("scrollback", 100) }.to raise_error(NotImplementedError)
  end

  it "emits option change events" do
    terminal = RTerm::Terminal.new
    changes = []

    terminal.onOptionChange { |payload| changes << payload }

    terminal.setOption(:cursorBlink, true)
    terminal.setOption("cursorStyle", :underline)

    expect(changes).to contain_exactly(
      hash_including(
        name: :cursor_blink,
        old_value: false,
        new_value: true
      ),
      hash_including(
        name: :cursor_style,
        old_value: :block,
        new_value: :underline
      )
    )
  end

  it "emits terminal events" do
    terminal = RTerm::Terminal.new
    data_event = []
    binary_event = []
    key_event = []
    selection_events = 0
    title_events = []
    scroll_events = 0

    terminal.onData { |data| data_event << data }
    terminal.onBinary { |data| binary_event << data }
    terminal.onKey { |payload| key_event << payload }
    terminal.onSelectionChange { |*| selection_events += 1 }
    terminal.onTitleChange { |title| title_events << title }
    terminal.onScroll { |*| scroll_events += 1 }

    terminal.input("input")
    terminal.binary("bin")
    terminal.key_event("x", text: "x")
    terminal.select(0, 0, 1)
    terminal.clearSelection
    terminal.write("\e]0;compat-title\a")
    terminal.scrollLines(1)

    expect(data_event).to include("input", "x")
    expect(binary_event).to eq(["bin".b])
    expect(key_event).to contain_exactly(hash_including(key: "x", keyCode: "x".ord))
    expect(selection_events).to be > 0
    expect(title_events).to eq(["compat-title"])
    expect(scroll_events).to be > 0
  end

  it "supports additional terminal events" do
    terminal = RTerm::Terminal.new
    focus_events = 0
    blur_events = 0
    bell_events = 0
    render_events = 0
    parsed_events = 0
    last_render = nil
    scroll_position = nil

    terminal.onFocus { focus_events += 1 }
    terminal.onBlur { blur_events += 1 }
    terminal.onBell { bell_events += 1 }
    terminal.onRender { |payload| render_events += 1; last_render = payload }
    terminal.onWriteParsed { parsed_events += 1 }
    terminal.onScroll { |position| scroll_position = position }

    terminal.open
    terminal.focus
    terminal.write("\a")

    expect(focus_events).to eq(1)
    expect(blur_events).to eq(0)
    expect(bell_events).to eq(1)
    expect(render_events).to eq(1)
    expect(last_render).to include(start: 0, end: 23)
    expect(parsed_events).to eq(1)

    terminal.scrollLines(1)
    expect(scroll_position).to be_a(Integer)
  end

  it "supports context menu handlers and event emission" do
    terminal = RTerm::Terminal.new
    events = []
    custom = []

    terminal.onContextMenu { |payload| events << payload }
    disposable = terminal.attachCustomContextMenuEventHandler do |payload|
      custom << payload
      payload[:col] != 1
    end

    expect(terminal.context_menu_event(1, 2)).to be false
    expect(events).to be_empty
    expect(custom.length).to eq(1)

    payload = terminal.context_menu_event(3, 4)
    expect(payload).to include(type: :context_menu, col: 3, row: 4, x: 3, y: 4)
    expect(events.last).to eq(payload)

    disposable.dispose
    terminal.context_menu_event(5, 6)
    expect(custom.length).to eq(2)
    expect(events.last).to include(col: 5, row: 6)
  end

  it "emits cursor move events with position data" do
    terminal = RTerm::Terminal.new
    movement = nil

    terminal.onCursorMove { |payload| movement = payload }
    terminal.write("\e[3;4H")

    expect(movement).to include(x: 3, y: 2, col: 3, row: 2)
  end

  it "supports scrollToCursor helper" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2, scrollback: 20)
    5.times { |i| terminal.writeln("line #{i}") }
    terminal.scrollToTop

    terminal.scrollToCursor

    active = terminal.internal.buffer_set.active
    expect(active.y_disp).to eq(active.y_base)
  end

  it "emits dispose callback" do
    terminal = RTerm::Terminal.new
    disposed = false

    terminal.onDispose { disposed = true }
    terminal.dispose

    expect(disposed).to be true
  end

  it "passes payload data in onWriteParsed callbacks" do
    terminal = RTerm::Terminal.new
    parsed_payloads = []

    terminal.onWriteParsed { |payload| parsed_payloads << payload }
    terminal.write("hello")

    expect(parsed_payloads).not_to be_empty
    expect(parsed_payloads.last).to include(
      row: 0,
      text: "hello",
      raw: "hello"
    )
  end

  it "calls write callbacks" do
    terminal = RTerm::Terminal.new
    calls = []

    terminal.write("hello") { |err| calls << err }
    terminal.writeln("world") { |err| calls << err }

    expect(calls).to eq([nil, nil])
  end

  it "calls write callbacks passed as positional arguments" do
    terminal = RTerm::Terminal.new
    calls = []

    terminal.write("hello", ->(err) { calls << err })
    terminal.writeln("world", ->(err) { calls << err })

    expect(calls).to eq([nil, nil])
  end

  it "accepts byte arrays for write and writeln data" do
    terminal = RTerm::Terminal.new(cols: 12, rows: 2)

    terminal.write([104, 105])
    terminal.writeln([33])

    expect(terminal.buffer.active.getLine(0).translateToString(true)).to start_with("hi!")
  end

  it "accepts wasUserInput forms for input" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2, scrollback: 20)
    emitted = []

    5.times { |i| terminal.writeln("line #{i}") }
    terminal.scrollToTop
    terminal.write("text")
    terminal.select(0, 0, 1)
    terminal.onData { |data| emitted << data }

    terminal.input("a", false)
    expect(terminal.getSelection).not_to eq("")
    expect(terminal.internal.buffer_set.active.y_disp).to eq(0)

    terminal.input("b", wasUserInput: false)
    expect(terminal.getSelection).not_to eq("")
    expect(terminal.internal.buffer_set.active.y_disp).to eq(0)

    terminal.input("c", was_user_input: true)
    expect(terminal.getSelection).to eq("")
    expect(terminal.internal.buffer_set.active.y_disp).to eq(terminal.internal.buffer_set.active.y_base)
    expect(emitted).to eq(%w[a b c])
  end

  it "passes selection payload on onSelectionChange callbacks" do
    terminal = RTerm::Terminal.new
    payloads = []

    terminal.onSelectionChange { |payload| payloads << payload }
    terminal.write("hello")
    terminal.select(0, 0, 5)

    expect(payloads).not_to be_empty
    expect(payloads.last).to include(
      selection_text: "hello",
      selectionText: "hello",
      selection: { type: :linear, column: 0, row: 0, length: 5 }
    )
  end

  it "refresh emits a render event" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2)
    events = []

    terminal.onRender { |payload| events << payload }
    terminal.refresh(0, 1)

    expect(events.last).to eq(start: 0, end: 1)
  end

  it "supports character joiner registration and deregistration" do
    terminal = RTerm::Terminal.new

    joiner_id = terminal.registerCharacterJoiner { |_line| nil }
    second_joiner = terminal.registerCharacterJoiner { |_line| false }

    expect(joiner_id).to be_a(Integer)
    expect(second_joiner).to eq(joiner_id + 1)

    expect(terminal.deregisterCharacterJoiner(joiner_id)).to be true
    expect(terminal.deregisterCharacterJoiner(joiner_id)).to be false
  end

  it "invokes character joiners when extracting selected text" do
    terminal = RTerm::Terminal.new
    saw = []

    terminal.registerCharacterJoiner do |line, row|
      saw << [line, row]
      []
    end

    terminal.write("hello")
    terminal.select(0, 0, 5)
    terminal.selection
    expect(saw).to include(["hello", 0])
  end

  it "supports selection aliases" do
    terminal = RTerm::Terminal.new
    terminal.write("open https://example.com")

    terminal.selectWord(0, 0)
    expect(terminal.getSelection).to eq("open")

    terminal.selectLine(0)
    expect(terminal.getSelection).to eq("open https://example.com")

    terminal.clearSelection
    terminal.selectUrl(5, 0)
    expect(terminal.getSelection).to eq("https://example.com")
  end

  it "supports additional selection aliases" do
    terminal = RTerm::Terminal.new(cols: 6, rows: 5)
    terminal.writeln("first")
    terminal.writeln("second")
    terminal.writeln("third")

    terminal.selectAll
    expect(terminal.getSelection).to eq("first\r\nsecond\r\nthird")
    terminal.clearSelection

    terminal.clearSelection
    terminal.selectLines(0, 1)
    expect(terminal.getSelection).to eq("first\r\nsecond")
  end

  it "returns selection position for linear selections" do
    terminal = RTerm::Terminal.new(cols: 8, rows: 2)
    terminal.write("hello")
    terminal.select(0, 0, 5)

    expect(terminal.getSelectionPosition).to eq(
      start: { x: 0, y: 0 },
      end: { x: 5, y: 0 }
    )
  end

  it "supports custom key event handlers with veto via disposable" do
    terminal = RTerm::Terminal.new
    emitted = []
    key_payloads = []

    terminal.on(:data) { |data| emitted << data }
    terminal.onKey { |payload| key_payloads << payload[:key] }
    disposable = terminal.attachCustomKeyEventHandler do |payload|
      payload[:key] != "a"
    end

    terminal.key_event("a", text: "a")
    expect(emitted).to eq([])
    expect(key_payloads).to eq([])

    terminal.key_event("b", text: "b")
    expect(emitted).to eq(["b"])
    expect(key_payloads).to eq(["b"])

    disposable.dispose
    terminal.key_event("a", text: "a")
    expect(emitted).to eq(%w[b a])
  end

  it "supports no-op headless focus/focus/refresh methods" do
    terminal = RTerm::Terminal.new

    expect { terminal.open; terminal.focus; terminal.blur; terminal.refresh }.not_to raise_error
  end

  it "supports marker registration and disposal" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2, scrollback: 20)
    8.times { |i| terminal.writeln("line #{i}") }

    marker = terminal.registerMarker
    expect(marker).not_to be_nil
    expect(marker.id).to be_a(Integer)
    expect(terminal.markers).to include(marker)

    start_line = marker.line
    terminal.scrollLines(-1)
    expect(marker.line).to eq(start_line)

    terminal.scrollLines(1)
    expect(marker.line).to eq(start_line)

    terminal_marker = terminal.register_marker(0)
    expect(terminal_marker).not_to be_nil

    terminal_marker.dispose
    expect(terminal.markers).not_to include(terminal_marker)
    expect(terminal_marker.line).to eq(-1)
    expect(terminal_marker.isDisposed).to be(true)

    terminal.clear
    expect(terminal.markers).to be_empty
    expect(terminal.getSelection).to eq("")
  end

  it "registers marker line offsets from the cursor" do
    terminal = RTerm::Terminal.new(cols: 10, rows: 4)
    terminal.write("abc")

    marker = terminal.registerMarker(1)

    expect(marker).not_to be_nil
    expect(marker.line).to eq(1)
    expect(terminal.registerMarker(-1)).to be_nil
  end

  it "hides markers while the alternate buffer is active" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2)
    marker = terminal.registerMarker

    terminal.internal.buffer_set.activate_alt_buffer
    expect(terminal.markers).to eq([])
    expect(terminal.getMarkers).to eq([])
    expect(terminal.registerMarker).to be_nil

    terminal.internal.buffer_set.activate_normal_buffer
    expect(terminal.markers).to include(marker)
  end

  it "supports addMarker alias with disposal callback" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2)
    disposed = []

    marker = terminal.addMarker do |disposed_marker|
      disposed << disposed_marker
    end

    expect(marker).to be_a(RTerm::Terminal::Marker)
    marker.dispose

    expect(disposed).to eq([marker])
  end

  it "supports string resources" do
    terminal = RTerm::Terminal.new

    expect(terminal.strings["promptLabel"]).to eq("Terminal input")
    expect(terminal.strings["tooMuchOutput"]).to include("output is too large")
  end

  it "returns terminal element and textarea properties" do
    terminal = RTerm::Terminal.new
    container = Object.new

    terminal.open(container)

    expect(terminal.element).to equal(container)
    expect(terminal.textarea).to be_nil
  end

  it "supports registerLinkProvider alias" do
    terminal = RTerm::Terminal.new

    terminal.registerLinkProvider do |_text, row|
      next [] if row != 0

      [{ url: "https://example.local/custom", row: row, col: 0, length: 25 }]
    end

    addon = terminal.instance_variable_get(:@addons).find { |item| item.is_a?(RTerm::Addon::WebLinks) }
    expect(addon).not_to be_nil
    expect(addon.find_links).to include(hash_including(url: "https://example.local/custom"))
  end

  it "supports registerLinkMatcher API" do
    terminal = RTerm::Terminal.new
    activated = []

    matcher_id = terminal.registerLinkMatcher(%r{@[a-z]+}, ->(_event, uri) { activated << uri })
    terminal.write("ping @alice")

    addon = terminal.instance_variable_get(:@addons).find { |item| item.is_a?(RTerm::Addon::WebLinks) }
    links = addon.find_links

    expect(matcher_id).to be_a(Integer)
    expect(links).to include(hash_including(url: "@alice", row: 0, col: 5, length: 6))
    expect(addon.open_link(links.first)).to be true
    expect(activated).to eq(["@alice"])
  end

  it "supports deregisterLinkMatcher removing matcher callbacks" do
    terminal = RTerm::Terminal.new
    activated = []

    matcher_id = terminal.registerLinkMatcher(%r{@[a-z]+}, ->(_event, uri) { activated << uri })
    terminal.write("ping @alice")

    expect(terminal.deregisterLinkMatcher(matcher_id)).to be true

    addon = terminal.instance_variable_get(:@addons).find { |item| item.is_a?(RTerm::Addon::Base) && item.respond_to?(:find_links) }
    links = addon.find_links

    expect(links).to be_empty
    expect(activated).to be_empty
  end

  it "supports registerDecoration alias" do
    terminal = RTerm::Terminal.new
    marker = terminal.registerMarker

    decoration = terminal.registerDecoration(marker, overviewRulerOptions: { color: "#ff00ff" })

    expect(terminal.instance_variable_get(:@decorations)).to include(decoration)
    expect(decoration.options).to eq(overviewRulerOptions: { color: "#ff00ff" })

    decoration.dispose
    expect(terminal.instance_variable_get(:@decorations)).not_to include(decoration)
  end

  it "supports clearTextureAtlas as no-op API" do
    terminal = RTerm::Terminal.new

    expect(terminal.clearTextureAtlas).to be(true)
  end

  it "supports getMarkers alias" do
    terminal = RTerm::Terminal.new
    marker = terminal.registerMarker

    expect(terminal.getMarkers).to include(marker)
  end

  it "supports onBufferChange event for buffer switching" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2)
    seen = []

    terminal.onBufferChange { |event| seen << event[:active].type }

    terminal.internal.buffer_set.activate_alt_buffer
    terminal.internal.buffer_set.activate_normal_buffer

    expect(seen).to eq(["alternate", "normal"])
  end

  it "supports copy API and emits clipboard payload" do
    terminal = RTerm::Terminal.new
    payload = nil

    terminal.on(:clipboard) { |entry| payload = entry }

    terminal.write("hello")
    terminal.select(0, 0, 5)
    copied = terminal.copy

    expect(copied).to eq("hello")
    expect(payload).to include(
      selection: "c",
      decoded: "hello",
      data: "aGVsbG8="
    )
  end

  it "supports loadAddon alias" do
    terminal = RTerm::Terminal.new
    addon = Class.new(RTerm::Addon::Base) do
      attr_reader :activated

      def activate(_terminal)
        @activated = true
      end
    end.new

    terminal.loadAddon(addon)

    expect(addon.activated).to be true
  end

  it "supports options assignment via options= setter" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2)

    terminal.options = { cursorBlink: true, cursorStyle: :underline, scrollOnUserInput: false }

    expect(terminal.getOption("cursorBlink")).to be true
    expect(terminal.getOption("cursorStyle")).to eq(:underline)
    expect(terminal.options.scroll_on_user_input).to be false
  end

  it "accepts camelCase constructor options" do
    terminal = RTerm::Terminal.new(cols: 4, rows: 2, cursorStyle: :underline, scrollOnUserInput: false)

    expect(terminal.getOption("cursorStyle")).to eq(:underline)
    expect(terminal.getOption(:scrollOnUserInput)).to be false
  end

  it "emits option change payload with camelCase keys too" do
    terminal = RTerm::Terminal.new
    event = nil

    terminal.onOptionChange { |payload| event = payload }

    terminal.setOption("cursorBlink", true)

    expect(event).to include(
      name: :cursor_blink,
      oldValue: false,
      newValue: true,
      name_camel: "cursorBlink"
    )
  end

  it "supports custom wheel event handlers" do
    terminal = RTerm::Terminal.new(rows: 2, cols: 4, scrollback: 20)
    5.times { |i| terminal.writeln("line #{i}") }

    seen = []
    terminal.attachCustomWheelEventHandler do |event|
      seen << event[:delta_y]
      event[:delta_y] <= 0
    end

    expect(terminal.mouse_wheel(1)).to be_nil
    expect(seen).to include(1)

    result = terminal.mouse_wheel(-2)
    expect(seen).to include(-2)
    expect(result).to eq(-2)
  end

  it "supports theme option updates" do
    terminal = RTerm::Terminal.new
    terminal.write("x")

    terminal.setOption("theme", { foreground: "#123456", background: "#654321", cursor: "#abcdef" })
    cell = terminal.buffer.active.getLine(0).getCell(0)
    colors = terminal.cell_colors(cell)

    expect(terminal.getOption("theme")).to include(foreground: "#123456", background: "#654321", cursor: "#abcdef")
    expect(colors[:foreground]).to eq("#123456")
    expect(colors[:background]).to eq("#654321")
  end

  it "accepts camelCase theme keys" do
    terminal = RTerm::Terminal.new

    terminal.setOption(
      :theme,
      {
        selectionBackground: "#112233",
        selectionForeground: "#445566",
        cursorAccentColor: "#778899",
        brightBlack: "#111111"
      }
    )

    expect(terminal.getOption(:theme)).to include(
      selection_background: "#112233",
      selection_foreground: "#445566",
      cursor_accent: "#778899",
      bright_black: "#111111"
    )
  end

  it "supports custom mouse event handlers with veto behavior" do
    terminal = RTerm::Terminal.new
    terminal.write("\e[?1000h")

    seen = []
    terminal.attachCustomMouseEventHandler do |payload|
      seen << payload[:button]
      payload[:button] != :left
    end

    blocked = terminal.mouse_event(button: :left, col: 1, row: 1)
    expect(seen).to eq([:left])
    expect(blocked).to be_nil

    blocked_sequence = terminal.mouse_event(button: :right, col: 2, row: 3, modifiers: %i[shift])
    expect(seen).to eq([:left, :right])
    expect(blocked_sequence).to be_a(String)
  end

  it "supports alternate buffer alias" do
    terminal = RTerm::Terminal.new

    expect(terminal.buffer.alternate).to eq(terminal.buffer.alt)
  end

  it "supports unicode namespace camelCase aliases" do
    terminal = RTerm::Terminal.new

    terminal.unicode.activeVersion = "11"

    expect(terminal.unicode.activeVersion).to eq("11")
  end
end
