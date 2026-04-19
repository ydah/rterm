# frozen_string_literal: true

RSpec.describe RTerm::Common::KeyEncoder do
  it "encodes arrow keys in normal cursor mode" do
    encoder = described_class.new

    expect(encoder.encode(:up)).to eq("\e[A")
    expect(encoder.encode(:down)).to eq("\e[B")
    expect(encoder.encode(:right)).to eq("\e[C")
    expect(encoder.encode(:left)).to eq("\e[D")
  end

  it "encodes arrow keys in application cursor mode" do
    encoder = described_class.new(application_cursor_keys_mode: true)

    expect(encoder.encode(:up)).to eq("\eOA")
    expect(encoder.encode(:left)).to eq("\eOD")
  end

  it "uses CSI modifier parameters for modified cursor keys" do
    encoder = described_class.new(application_cursor_keys_mode: true)

    expect(encoder.encode(:up, modifiers: [:shift])).to eq("\e[1;2A")
    expect(encoder.encode(:right, modifiers: [:ctrl, :alt])).to eq("\e[1;7C")
  end

  it "encodes navigation keys" do
    encoder = described_class.new

    expect(encoder.encode(:home)).to eq("\e[H")
    expect(encoder.encode(:end, modifiers: [:ctrl])).to eq("\e[1;5F")
    expect(encoder.encode(:delete)).to eq("\e[3~")
    expect(encoder.encode(:page_down, modifiers: [:shift])).to eq("\e[6;2~")
  end

  it "encodes function keys" do
    encoder = described_class.new

    expect(encoder.encode(:f1)).to eq("\eOP")
    expect(encoder.encode(:f4, modifiers: [:shift])).to eq("\e[1;2S")
    expect(encoder.encode(:f5)).to eq("\e[15~")
    expect(encoder.encode(:f12, modifiers: [:ctrl])).to eq("\e[24;5~")
  end

  it "encodes control and printable text keys" do
    encoder = described_class.new

    expect(encoder.encode(:enter)).to eq("\r")
    expect(encoder.encode(:backspace)).to eq("\x7F")
    expect(encoder.encode("a", modifiers: [:ctrl])).to eq("\x01")
    expect(encoder.encode("x", modifiers: [:alt])).to eq("\ex")
    expect(encoder.encode(:ignored_unknown_name)).to eq("ignored_unknown_name")
  end

  it "encodes keypad keys according to keypad mode" do
    normal = described_class.new
    application = described_class.new(application_keypad_mode: true)

    expect(normal.encode(:keypad_1)).to eq("1")
    expect(normal.encode(:keypad_enter)).to eq("\r")
    expect(application.encode(:keypad_1)).to eq("\eOq")
    expect(application.encode(:keypad_enter)).to eq("\eOM")
  end

  it "uses text payloads directly with alt prefix support" do
    encoder = described_class.new

    expect(encoder.encode(:any, text: "é")).to eq("é")
    expect(encoder.encode(:any, text: "é", modifiers: [:alt])).to eq("\eé")
  end
end
