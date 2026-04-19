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
      config.allowed_origins = []
      config.max_message_bytes = nil
      config.rate_limit = nil
      config.heartbeat_timeout = nil
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
      config.allowed_origins = []
      config.max_message_bytes = nil
      config.rate_limit = nil
      config.heartbeat_timeout = nil
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
      config.allowed_origins = ["https://example.com"]
      config.max_message_bytes = 4096
      config.rate_limit = { limit: 10, interval: 1 }
      config.heartbeat_timeout = 45
    end

    expect(described_class.config.default_command).to eq("/bin/bash")
    expect(described_class.config.max_sessions).to eq(2)
    expect(described_class.config.terminal_options).to eq({ cols: 120, rows: 40 })
    expect(described_class.config.session_timeout).to eq(60)
    expect(described_class.config.idle_timeout).to eq(30)
    expect(described_class.config.authenticator.call(nil)).to be true
    expect(described_class.config.output_queue_limit).to eq(2048)
    expect(described_class.config.allowed_origins).to eq(["https://example.com"])
    expect(described_class.config.max_message_bytes).to eq(4096)
    expect(described_class.config.rate_limit).to eq({ limit: 10, interval: 1 })
    expect(described_class.config.heartbeat_timeout).to eq(45)
  end

  it "builds a session manager from configuration" do
    described_class.configure do |config|
      config.max_sessions = 3
      config.max_message_bytes = 4096
    end

    manager = described_class.session_manager

    expect(manager.max_sessions).to eq(3)
  end

  it "checks allowed origins" do
    described_class.configure do |config|
      config.allowed_origins = ["https://example.com"]
    end

    expect(described_class.send(:origin_allowed?, "HTTP_ORIGIN" => "https://example.com")).to be true
    expect(described_class.send(:origin_allowed?, "HTTP_ORIGIN" => "https://evil.example")).to be false
  end

  it "checks message size limits" do
    described_class.configure do |config|
      config.max_message_bytes = 3
    end

    expect(described_class.send(:message_too_large?, "abcd")).to be true
    expect(described_class.send(:message_too_large?, "abc")).to be false
  end
end
