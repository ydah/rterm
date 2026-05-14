# frozen_string_literal: true

RSpec.describe RTerm::Addon::Image do
  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }
  let(:addon) { described_class.new }

  before do
    terminal.load_addon(addon)
  end

  it "tracks image payload events" do
    seen = []
    addon.on_image { |payload| seen << payload }

    terminal.write("\ePqABCDEF\e\\")

    expect(seen.first).to include(protocol: :sixel, data: "ABCDEF")
    expect(addon.images).to include(seen.first)
    expect(addon.count).to eq(1)
    expect(addon.empty?).to be(false)
  end

  it "filters images by protocol" do
    terminal.write("\ePqABCDEF\e\\")
    terminal.write("\e]1337;File=name=test.png;inline=1:AAAA\a")

    expect(addon.protocols).to contain_exactly(:sixel, :iterm2)
    expect(addon.by_protocol(:sixel).length).to eq(1)
    expect(addon.byProtocol("iterm2").first).to include(protocol: :iterm2)
  end

  it "finds images by occupied cell" do
    terminal.write("\e]1337;File=name=test.png;inline=1;width=3;height=2:AAAA\a")

    image = addon.at(1, 2)

    expect(image).to include(protocol: :iterm2)
    expect(addon.at(3, 2)).to be_nil
  end

  it "clears images by protocol or buffer" do
    cleared = []
    addon.on_clear { |items| cleared << items }
    terminal.write("\ePqABCDEF\e\\")
    terminal.write("\e]1337;File=name=test.png;inline=1:AAAA\a")

    removed = addon.clear(protocol: :sixel)

    expect(removed.map { |image| image[:protocol] }).to eq([:sixel])
    expect(addon.images.map { |image| image[:protocol] }).to eq([:iterm2])
    expect(cleared.first).to eq(removed)

    addon.clear(buffer: :normal)
    expect(addon.images).to be_empty
  end

  it "delegates image decode and render requests" do
    decoded = []
    rendered = []
    decode_events = []
    render_events = []
    addon.registerDecoder(:sixel) do |image|
      decoded << image
      { bytes: image[:data].bytesize, format: image[:protocol] }
    end
    renderer = lambda do |request|
      rendered << request
      :queued
    end
    addon_with_renderer = described_class.new(renderer: renderer)
    terminal.load_addon(addon_with_renderer)
    addon_with_renderer.registerDecoder(:sixel) { |image| { bytes: image[:data].bytesize } }
    addon_with_renderer.onDecode { |payload| decode_events << payload }
    addon_with_renderer.onRenderRequest { |payload| render_events << payload }

    terminal.write("\ePqABCDEF\e\\")

    image = addon.by_protocol(:sixel).first
    expect(addon.decode(image)).to include(result: { bytes: 6, format: :sixel })

    request = addon_with_renderer.render(addon_with_renderer.byProtocol(:sixel).first, target: :canvas)
    expect(decoded.first).to include(protocol: :sixel, data: "ABCDEF")
    expect(request).to include(target: :canvas, decoded: { bytes: 6 }, result: :queued)
    expect(rendered.first).to include(protocol: :sixel, target: :canvas)
    expect(decode_events.last).to include(protocol: :sixel, result: { bytes: 6 })
    expect(render_events.last).to include(protocol: :sixel, result: :queued)
    expect(addon_with_renderer.renderRequests.last).to include(protocol: :sixel, result: :queued)
  end

  it "renders all images with filters" do
    requests = []
    addon_with_renderer = described_class.new(renderer: ->(request) {
      requests << request
      :queued
    })
    terminal.load_addon(addon_with_renderer)
    terminal.write("\ePqABCDEF\e\\")
    terminal.write("\e]1337;File=name=test.png;inline=1:AAAA\a")

    rendered = addon_with_renderer.renderAll(protocol: :iterm2, buffer: :normal, target: :inline)

    expect(rendered.length).to eq(1)
    expect(rendered.first).to include(protocol: :iterm2, target: :inline)
    expect(requests.length).to eq(1)
  end

  it "stops forwarding events after disposal" do
    seen = []
    addon.onImage { |payload| seen << payload }
    addon.dispose

    terminal.write("\ePqABCDEF\e\\")

    expect(seen).to be_empty
  end
end
