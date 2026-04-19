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
      config.attach_policy = :multiple
      config.binary_mode = :auto
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
      config.attach_policy = :multiple
      config.binary_mode = :auto
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
      config.attach_policy = :single
      config.binary_mode = :required
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
    expect(described_class.config.attach_policy).to eq(:single)
    expect(described_class.config.binary_mode).to eq(:required)
  end

  it "builds a session manager from configuration" do
    described_class.configure do |config|
      config.max_sessions = 3
      config.max_message_bytes = 4096
    end

    manager = described_class.session_manager

    expect(manager.max_sessions).to eq(3)
  end

  it "applies secure defaults and allows overrides" do
    described_class.configure_secure_defaults do |config|
      config.allowed_origins = ["https://app.example"]
      config.rate_limit = { interval: 2.0, limit: 10 }
      config.terminal_options = config.terminal_options.merge(scrollback: 5_000)
    end

    expect(described_class.config.allowed_origins).to eq(["https://app.example"])
    expect(described_class.config.max_message_bytes).to eq(64 * 1024)
    expect(described_class.config.heartbeat_timeout).to eq(30)
    expect(described_class.config.rate_limit).to eq({ interval: 2.0, limit: 10 })
    expect(described_class.config.attach_policy).to eq(:single)
    expect(described_class.config.output_queue_limit).to eq(1_048_576)
    expect(described_class.config.binary_mode).to eq(:auto)
    expect(described_class.config.terminal_options).to include(
      clipboard_enabled: false,
      clipboard_max_bytes: 64 * 1024,
      scrollback: 5_000
    )
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

  it "negotiates binary output per socket" do
    socket = FakeSocket.new
    described_class.send(:wire_socket, socket)

    socket.emit_message(RTerm::BrowserBridge::ProtocolHandler.encode("negotiate", payload: { "binary" => true }))

    response = JSON.parse(socket.sent.last)
    expect(response["type"]).to eq("negotiated")
    expect(response["payload"]["binary"]).to be true
  end

  it "rejects binary frames when disabled" do
    described_class.configure do |config|
      config.binary_mode = :disabled
    end
    socket = FakeSocket.new
    described_class.send(:wire_socket, socket)

    socket.emit_message(RTerm::BrowserBridge::ProtocolHandler.encode_binary(:input, "x"))

    response = JSON.parse(socket.sent.last)
    expect(response["type"]).to eq("error")
    expect(response["payload"]["code"]).to eq("binary_disabled")
  end

  it "sends output as binary after negotiation" do
    socket = FakeSocket.new
    described_class.send(:wire_socket, socket)
    socket.emit_message(RTerm::BrowserBridge::ProtocolHandler.encode("negotiate", payload: { "binary" => true }))

    session_id = described_class.session_manager.create_session
    described_class.session_manager.queue_output(session_id, "abc")

    decoded = RTerm::BrowserBridge::ProtocolHandler.decode_binary(socket.sent.last)
    expect(decoded).to eq({ type: "output", session_id: session_id, payload: { "data" => "abc" } })
  end

  it "disposes socket callbacks when the socket closes" do
    socket = FakeSocket.new
    described_class.send(:wire_socket, socket)
    session_id = described_class.session_manager.create_session

    described_class.session_manager.queue_output(session_id, "before")
    sent_count = socket.sent.length

    socket.emit_close
    described_class.session_manager.queue_output(session_id, "after")

    expect(socket.sent.length).to eq(sent_count)
  end

  class FakeSocket
    attr_reader :sent

    def initialize
      @handlers = {}
      @sent = []
    end

    def on(event, &block)
      @handlers[event] = block
    end

    def send(data)
      @sent << data
    end

    def emit_message(data)
      @handlers.fetch(:message).call(FakeMessage.new(data))
    end

    def emit_close
      @handlers.fetch(:close).call(Object.new)
    end
  end

  FakeMessage = Struct.new(:data)
end
