# frozen_string_literal: true

RSpec.describe RTerm::Addon::Attach do
  class FakeAttachSocket
    attr_reader :sent

    def initialize
      @sent = []
      @listeners = Hash.new { |hash, key| hash[key] = [] }
    end

    def on(event, &block)
      @listeners[event] << block
      RTerm::Common::Disposable.new { @listeners[event].delete(block) }
    end

    def send(data)
      @sent << data
    end

    def trigger(event, data = nil)
      payload = event == :message ? Struct.new(:data).new(data) : data
      @listeners[event].dup.each { |listener| listener.call(payload) }
    end
  end

  let(:terminal) { RTerm::Terminal.new(cols: 20, rows: 4) }
  let(:socket) { FakeAttachSocket.new }
  let(:addon) { described_class.new(socket) }

  before do
    terminal.load_addon(addon)
  end

  it "forwards terminal input to the socket" do
    terminal.input("ls\r")

    expect(socket.sent).to eq(["ls\r"])
  end

  it "writes socket messages to the terminal" do
    seen = []
    addon.on(:message) { |payload| seen << payload }

    socket.trigger(:message, "ready")

    expect(terminal.buffer.active.get_line(0).to_string).to eq("ready")
    expect(seen).to eq(["ready"])
  end

  it "can disable terminal-to-socket forwarding" do
    passive_socket = FakeAttachSocket.new
    passive = described_class.new(passive_socket, bidirectional: false)
    passive_terminal = RTerm::Terminal.new(cols: 20, rows: 4)
    passive_terminal.load_addon(passive)

    passive_terminal.input("ignored")
    passive_socket.trigger(:message, "output")

    expect(passive_socket.sent).to be_empty
    expect(passive_terminal.buffer.active.get_line(0).to_string).to eq("output")
  end

  it "supports array byte messages" do
    socket.trigger(:message, [65, 66, 67])

    expect(terminal.buffer.active.get_line(0).to_string).to eq("ABC")
  end

  it "stops forwarding after disposal" do
    addon.dispose

    terminal.input("ignored")
    socket.trigger(:message, "ignored")

    expect(socket.sent).to be_empty
    expect(terminal.buffer.active.get_line(0).to_string).to eq("")
  end
end
