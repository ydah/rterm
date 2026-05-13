# frozen_string_literal: true

RSpec.describe RTerm::Addon::Progress do
  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }
  let(:addon) { described_class.new }

  before do
    terminal.load_addon(addon)
  end

  it "captures progress sequences" do
    changes = []
    events = []
    addon.on_change { |payload| changes << payload }
    terminal.on(:progress) { |payload| events << payload }

    terminal.write("\e]9;4;1;25\a")

    expect(addon.state).to include(state: 1, value: 25, name: :normal)
    expect(changes.last).to include(state: 1, value: 25, name: :normal)
    expect(events.last).to include(state: 1, value: 25, name: :normal)
  end

  it "clamps progress values" do
    terminal.write("\e]9;4;1;250\a")

    expect(addon.value).to eq(100)
  end

  it "supports all progress states" do
    terminal.write("\e]9;4;2;80\a")
    expect(addon.state).to include(state: 2, value: 80, name: :error)

    terminal.write("\e]9;4;3\a")
    expect(addon.state).to include(state: 3, value: 0, name: :indeterminate)

    terminal.write("\e]9;4;4;40\a")
    expect(addon.state).to include(state: 4, value: 40, name: :paused)

    terminal.write("\e]9;4;0;90\a")
    expect(addon.state).to include(state: 0, value: 0, name: :none)
  end

  it "ignores unrelated OSC 9 payloads" do
    terminal.write("\e]9;notify\a")

    expect(addon.state).to include(state: 0, value: 0, name: :none)
  end

  it "supports direct state updates" do
    seen = []
    addon.onChange { |payload| seen << payload }

    addon.set(12)
    addon.error
    addon.indeterminate
    addon.pause(60)
    addon.remove

    expect(seen.map { |payload| payload[:state] }).to eq([1, 2, 3, 4, 0])
    expect(addon.stateCode).to eq(0)
  end

  it "disposes parser subscriptions" do
    addon.dispose

    terminal.write("\e]9;4;1;25\a")

    expect(addon.state).to include(state: 0, value: 0, name: :none)
  end
end
