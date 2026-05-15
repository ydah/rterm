# frozen_string_literal: true

RSpec.describe RTerm::Addon::WebFonts do
  it "registers font faces and exposes css" do
    addon = described_class.new(false)
    registered = []
    addon.on(:register) { |face| registered << face }

    face = addon.registerFont(
      "JetBrains Mono",
      "url('/fonts/jetbrains.woff2') format('woff2')",
      weight: 400,
      style: "normal",
      display: "swap"
    )

    expect(face).to include(
      family: "JetBrains Mono",
      source: "url('/fonts/jetbrains.woff2') format('woff2')",
      weight: 400,
      style: "normal",
      display: "swap",
      status: :registered
    )
    expect(registered).to eq([face])
    expect(addon.fontFaceCss).to include('@font-face')
    expect(addon.fontFaceCss).to include('font-family: "JetBrains Mono";')
    expect(addon.fontFaceCss).to include("font-weight: 400;")
    expect(addon.fontFaceCss).to include("font-display: swap;")
    expect(addon.fontFaceCss).to include("src: url('/fonts/jetbrains.woff2') format('woff2');")
  end

  it "loads registered font families and emits events" do
    terminal = RTerm::Terminal.new
    addon = described_class.new(false)
    seen = []
    terminal_events = []

    addon.onLoad { |face| seen << face }
    terminal.on(:font_load) { |face| terminal_events << face }
    terminal.load_addon(addon)

    addon.register_font(family: "Cascadia Code", src: "url('/fonts/cascadia.woff2')", weight: "400")
    loaded = addon.loadFonts("Cascadia Code")

    expect(loaded.length).to eq(1)
    expect(loaded.first).to include(family: "Cascadia Code", status: :loaded)
    expect(addon.loaded?("Cascadia Code")).to be true
    expect(addon.loadedFamilies).to eq(["Cascadia Code"])
    expect(seen).to eq(loaded)
    expect(terminal_events).to eq(loaded)
  end

  it "rejects unknown font families" do
    addon = described_class.new(false)

    expect { addon.loadFonts("Missing Font") }.to raise_error(ArgumentError, /Missing Font/)
  end

  it "relayouts by toggling terminal font family" do
    terminal = RTerm::Terminal.new(fontFamily: '"JetBrains Mono", monospace')
    addon = described_class.new(false)
    changes = []
    relayouts = []

    terminal.onOptionChange { |payload| changes << payload if payload[:name] == :font_family }
    addon.onRelayout { |payload| relayouts << payload }
    terminal.load_addon(addon)
    addon.register_font("JetBrains Mono", "url('/fonts/jetbrains.woff2') format('woff2')")

    expect(addon.relayout).to be true
    expect(terminal.getOption(:font_family)).to eq('"JetBrains Mono", monospace')
    expect(changes.map { |payload| payload[:new_value] }).to eq(["monospace", '"JetBrains Mono", monospace'])
    expect(addon.loaded?("JetBrains Mono")).to be true
    expect(relayouts.last).to include(
      font_family: '"JetBrains Mono", monospace',
      fallback: "monospace"
    )
  end

  it "runs initial relayout when activated" do
    terminal = RTerm::Terminal.new(fontFamily: "Fira Code")
    addon = described_class.new(fonts: [{ family: "Fira Code", src: "url('/fonts/fira.woff2')" }])

    terminal.load_addon(addon)

    expect(addon.loaded?("Fira Code")).to be true
    expect(terminal.getOption("fontFamily")).to eq("Fira Code")
  end

  it "resolves fallback font families" do
    terminal = RTerm::Terminal.new(fontFamily: '"JetBrains Mono", "Fira Code", monospace')
    addon = described_class.new(false)
    terminal.load_addon(addon)
    addon.register_font("JetBrains Mono", "url('/fonts/jetbrains.woff2')")
    addon.register_font("Fira Code", "url('/fonts/fira.woff2')")
    addon.loadFonts("Fira Code")

    resolved = addon.resolveFontFamily(fallback: "serif")

    expect(resolved).to include(
      requested: ["JetBrains Mono", "Fira Code", "monospace"],
      selected: "Fira Code",
      fallback: "serif"
    )
    expect(resolved[:fontFamily]).to eq('"JetBrains Mono", "Fira Code", monospace, serif')
  end

  it "estimates cell size and emits measure events" do
    terminal = RTerm::Terminal.new(fontSize: 20, lineHeight: 1.2, letterSpacing: 1)
    addon = described_class.new(false)
    measures = []
    terminal_events = []

    addon.onMeasure { |payload| measures << payload }
    terminal.on(:font_measure) { |payload| terminal_events << payload }
    terminal.load_addon(addon)

    measurement = addon.measureCell

    expect(measurement).to include(width: 13.0, height: 24.0, source: :estimated)
    expect(measurement[:font]).to include(selected: "courier-new")
    expect(measures).to eq([measurement])
    expect(terminal_events).to eq([measurement])
  end
end
