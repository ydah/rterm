# frozen_string_literal: true

RSpec.describe RTerm::TerminalOptions do
  it "provides xterm-compatible defaults" do
    options = described_class.new

    expect(options.cols).to eq(80)
    expect(options.rows).to eq(24)
    expect(options.scrollback).to eq(1000)
    expect(options.cursor_style).to eq(:block)
    expect(options.convert_eol).to be false
    expect(options.clipboard_enabled).to be true
    expect(options.clipboard_max_bytes).to eq(1_048_576)
  end

  it "accepts overrides and exposes hash-style access" do
    options = described_class.new(cols: 120, rows: 40, cursor_blink: true)

    expect(options.cols).to eq(120)
    expect(options[:rows]).to eq(40)
    expect(options.cursor_blink).to be true
  end

  it "duplicates nested option hashes" do
    options = described_class.new(window_options: { restore_win: true })
    copy = options.to_h

    copy[:window_options][:restore_win] = false

    expect(options.window_options[:restore_win]).to be true
  end

  it "rejects unknown options" do
    expect { described_class.new(unknown: true) }.to raise_error(ArgumentError, /Unknown terminal option/)
  end
end

RSpec.describe RTerm::Theme do
  it "has xterm-style default colors" do
    theme = described_class.new

    expect(theme.foreground).to eq("#ffffff")
    expect(theme.background).to eq("#000000")
    expect(theme.red).to eq("#cd3131")
    expect(theme.bright_white).to eq("#ffffff")
  end

  it "supports overrides and serialization" do
    theme = described_class.new(foreground: "#eeeeee", cursor: "#ff00ff")

    expect(theme.foreground).to eq("#eeeeee")
    expect(theme.to_h[:cursor]).to eq("#ff00ff")
  end

  it "rejects unknown colors" do
    expect { described_class.new(nope: "#000000") }.to raise_error(ArgumentError, /Unknown theme color/)
  end
end
