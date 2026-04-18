# frozen_string_literal: true

RSpec.describe RTerm::BrowserBridge::WebSocketServer do
  around do |example|
    described_class.configure do |config|
      config.default_command = nil
      config.max_sessions = 10
      config.terminal_options = {}
    end
    example.run
    described_class.configure do |config|
      config.default_command = nil
      config.max_sessions = 10
      config.terminal_options = {}
    end
  end

  it "stores configuration" do
    described_class.configure do |config|
      config.default_command = "/bin/bash"
      config.max_sessions = 2
      config.terminal_options = { cols: 120, rows: 40 }
    end

    expect(described_class.config.default_command).to eq("/bin/bash")
    expect(described_class.config.max_sessions).to eq(2)
    expect(described_class.config.terminal_options).to eq({ cols: 120, rows: 40 })
  end

  it "builds a session manager from configuration" do
    described_class.configure do |config|
      config.max_sessions = 3
    end

    manager = described_class.session_manager

    expect(manager.max_sessions).to eq(3)
  end
end
