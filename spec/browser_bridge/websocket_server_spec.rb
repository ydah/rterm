# frozen_string_literal: true

RSpec.describe RTerm::BrowserBridge::WebSocketServer do
  around do |example|
    described_class.configure do |config|
      config.default_command = nil
      config.max_sessions = 10
      config.terminal_options = {}
      config.session_timeout = nil
      config.idle_timeout = nil
      config.authenticator = nil
      config.output_queue_limit = 1_048_576
    end
    example.run
    described_class.configure do |config|
      config.default_command = nil
      config.max_sessions = 10
      config.terminal_options = {}
      config.session_timeout = nil
      config.idle_timeout = nil
      config.authenticator = nil
      config.output_queue_limit = 1_048_576
    end
  end

  it "stores configuration" do
    described_class.configure do |config|
      config.default_command = "/bin/bash"
      config.max_sessions = 2
      config.terminal_options = { cols: 120, rows: 40 }
      config.session_timeout = 60
      config.idle_timeout = 30
      config.authenticator = ->(_env) { true }
      config.output_queue_limit = 2048
    end

    expect(described_class.config.default_command).to eq("/bin/bash")
    expect(described_class.config.max_sessions).to eq(2)
    expect(described_class.config.terminal_options).to eq({ cols: 120, rows: 40 })
    expect(described_class.config.session_timeout).to eq(60)
    expect(described_class.config.idle_timeout).to eq(30)
    expect(described_class.config.authenticator.call(nil)).to be true
    expect(described_class.config.output_queue_limit).to eq(2048)
  end

  it "builds a session manager from configuration" do
    described_class.configure do |config|
      config.max_sessions = 3
    end

    manager = described_class.session_manager

    expect(manager.max_sessions).to eq(3)
  end
end
