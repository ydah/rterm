# frozen_string_literal: true

RSpec.describe RTerm::Addon::Clipboard do
  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }
  let(:addon) { described_class.new }

  before do
    terminal.load_addon(addon)
  end

  it "stores text written through the addon" do
    payload = addon.write_text("hello")

    expect(payload).to include(selection: "clipboard", decoded: "hello", allowed: true)
    expect(addon.read_text).to eq("hello")
  end

  it "tracks text copied through the terminal API" do
    terminal.write("copy me")
    terminal.select(0, 0, 7)

    copied = addon.copy_selection

    expect(copied).to eq("copy me")
    expect(addon.read_text).to eq("copy me")
  end

  it "pastes stored text through terminal input" do
    data = []
    terminal.on(:data) { |payload| data << payload }
    addon.write_text("pasted")

    emitted = addon.paste

    expect(emitted).to eq("pasted")
    expect(data).to include("pasted")
  end

  it "uses external read and write handlers" do
    written = []
    external = described_class.new(read: ->(_selection) { "external" }, write: ->(text, payload) {
      written << [text, payload[:selection]]
    })
    terminal.load_addon(external)

    external.write_text("stored", selection: :primary)

    expect(written).to eq([["stored", "primary"]])
    external.clear(:primary)
    expect(external.read_text(selection: :primary)).to eq("external")
  end

  it "emits change events for accepted clipboard writes" do
    changes = []
    addon.on_change { |payload| changes << payload }

    terminal.copy("changed")

    expect(changes.first).to include(text: "changed", selection: "c")
  end

  it "clears all or selected entries" do
    addon.write_text("one")
    addon.write_text("two", selection: :primary)

    addon.clear(:primary)
    expect(addon.read_text(selection: :primary)).to be_nil
    expect(addon.read_text).to eq("one")

    addon.clear
    expect(addon.store).to be_empty
  end
end
