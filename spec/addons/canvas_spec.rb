# frozen_string_literal: true

RSpec.describe RTerm::Addon::Canvas do
  it "activates with renderer capabilities and emits change events" do
    terminal = RTerm::Terminal.new(cols: 16, rows: 5)
    addon = described_class.new(capabilities: { alpha: false })
    changes = []
    terminal_events = []

    addon.onChange { |payload| changes << payload }
    terminal.on(:renderer_change) { |payload| terminal_events << payload }

    terminal.load_addon(addon)

    expect(addon).to be_active
    expect(addon.rendererType).to eq(:canvas)
    expect(addon.capabilities).to include(
      type: :canvas,
      accelerated: false,
      context_type: "2d",
      texture_atlas: false,
      render_cache: true,
      alpha: false
    )
    expect(addon.state).to include(
      active: true,
      context_lost: false,
      last_resize: { cols: 16, rows: 5 }
    )
    expect(changes.last).to include(event: :activate)
    expect(terminal_events.last).to include(event: :activate)
  end

  it "tracks render, resize, and option updates" do
    terminal = RTerm::Terminal.new(cols: 10, rows: 3)
    addon = described_class.new
    renders = []

    terminal.load_addon(addon)
    addon.on(:render) { |payload| renders << payload }

    terminal.refresh(1, 2)
    terminal.resize(20, 5)
    terminal.setOption("fontFamily", "Fira Code")

    expect(addon.lastRender).to eq(start: 1, end: 2, rows: [1, 2])
    expect(renders.last).to eq(start: 1, end: 2, rows: [1, 2])
    expect(addon.lastResize).to eq(cols: 20, rows: 5)
    expect(addon.state[:last_option_change]).to include(
      name: :font_family,
      new_value: "Fira Code"
    )
  end

  it "records render cache clears through terminal events" do
    terminal = RTerm::Terminal.new
    addon = described_class.new
    seen = []
    terminal_events = []

    addon.onRenderCacheClear { |payload| seen << payload }
    terminal.on(:canvas_render_cache_clear) { |payload| terminal_events << payload }
    terminal.load_addon(addon)

    expect(addon.clearRenderCache).to be true
    expect(terminal.clearTextureAtlas).to be true

    expect(addon.state[:render_cache_clears]).to eq(2)
    expect(seen.map { |payload| payload[:source] }).to eq(%i[terminal terminal])
    expect(terminal_events.length).to eq(2)
  end

  it "reports context loss and restore lifecycle" do
    terminal = RTerm::Terminal.new(rows: 2)
    addon = described_class.new(context: :initial)
    losses = []
    restores = []
    renders = []

    addon.onContextLoss { |payload| losses << payload }
    addon.onContextRestore { |payload| restores << payload }
    addon.on(:render) { |payload| renders << payload }
    terminal.load_addon(addon)

    expect(addon.loseContext("reset")).to be true
    expect(addon.loseContext("again")).to be false
    expect(addon).to be_context_lost
    expect(losses.last).to include(event: :context_loss, reason: "reset", context_lost: true)

    expect(addon.restoreContext(:restored)).to be true
    expect(addon.restoreContext).to be false
    expect(addon).not_to be_context_lost
    expect(addon.context).to eq(:restored)
    expect(restores.last).to include(event: :context_restore, context_lost: false)
    expect(renders.last).to eq(start: 0, end: 1, rows: [0, 1])
  end

  it "attaches renderer references and disposes subscriptions" do
    terminal = RTerm::Terminal.new
    addon = described_class.new

    terminal.load_addon(addon)
    state = addon.attachRenderer(:renderer, context: :context, capabilities: { desynchronized: true })
    addon.dispose
    terminal.refresh(0, 0)

    expect(state[:capabilities]).to include(desynchronized: true)
    expect(addon.renderer).to eq(:renderer)
    expect(addon.context).to eq(:context)
    expect(addon).not_to be_active
    expect(addon.lastRender).to be_nil
  end
end
