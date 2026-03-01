# frozen_string_literal: true

RSpec.describe RTerm::Pty do
  before do
    skip "PTY not available" unless defined?(::PTY)
  end

  describe "#initialize" do
    it "spawns a process" do
      pty = described_class.new(command: "/bin/echo", args: ["hello"])
      expect(pty.pid).to be_a(Integer)
      pty.close
    end
  end

  describe "#on_data" do
    it "receives output from the spawned process" do
      pty = described_class.new(command: "/bin/echo", args: ["hello"])
      received = +""
      pty.on_data { |data| received << data }
      sleep 0.5
      pty.close
      expect(received).to include("hello")
    end
  end

  describe "#write" do
    it "sends data to the process" do
      pty = described_class.new(command: "/bin/cat")
      received = +""
      pty.on_data { |data| received << data }
      sleep 0.1
      pty.write("test input\n")
      sleep 0.5
      pty.close
      expect(received).to include("test input")
    end
  end

  describe "#alive?" do
    it "returns true for a running process" do
      pty = described_class.new(command: "/bin/cat")
      expect(pty.alive?).to be true
      pty.kill
      sleep 0.2
      pty.close
    end

    it "returns false after the process exits" do
      pty = described_class.new(command: "/bin/echo", args: ["done"])
      sleep 0.3
      pty.close
      expect(pty.alive?).to be false
    end
  end

  describe "#close" do
    it "cleans up resources" do
      pty = described_class.new(command: "/bin/cat")
      pty.on_data { |_| }
      sleep 0.1
      expect { pty.close }.not_to raise_error
    end
  end

  describe "#resize" do
    it "changes the PTY dimensions" do
      pty = described_class.new(command: "/bin/bash", cols: 80, rows: 24)
      received = +""
      pty.on_data { |data| received << data }
      sleep 0.2
      pty.resize(120, 40)
      sleep 0.1
      pty.write("stty size\n")
      sleep 0.5
      pty.close
      expect(received).to include("40 120")
    end
  end

  describe "#on_exit" do
    it "calls exit callback when process exits" do
      pty = described_class.new(command: "/bin/echo", args: ["bye"])
      exit_code = nil
      pty.on_exit { |code| exit_code = code }
      pty.on_data { |_| }
      sleep 1
      pty.close
      expect(exit_code).to eq(0)
    end
  end
end
