# frozen_string_literal: true

require "tmpdir"

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

    it "spawns a process in the requested cwd" do
      pty = described_class.new(command: RbConfig.ruby, args: ["-e", "puts Dir.pwd"], cwd: Dir.tmpdir)
      received = +""
      pty.on_data { |data| received << data }

      wait_until { received.include?(Dir.tmpdir) || pty.exit_status }
      pty.close

      expect(received).to include(Dir.tmpdir)
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

    it "handles large output in bounded read chunks" do
      size = 128 * 1024
      pty = described_class.new(
        command: RbConfig.ruby,
        args: ["-e", "print 'x' * #{size}"],
        read_chunk_size: 8192
      )
      received = +""
      pty.on_data { |data| received << data }

      wait_until { received.bytesize >= size || pty.exit_status }
      pty.close

      expect(received.bytesize).to eq(size)
      expect(pty.exit_status).to eq(0)
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

    it "can close stdin" do
      pty = described_class.new(command: RbConfig.ruby, args: ["-e", "STDIN.read; puts 'done'"])
      received = +""
      pty.on_data { |data| received << data }

      expect(pty.close_stdin).to be true
      wait_until { received.include?("done") || pty.exit_status }
      pty.close

      expect(received).to include("done")
    end
  end

  describe "#pause and #resume" do
    it "pauses and resumes background reads" do
      pty = described_class.new(command: RbConfig.ruby, args: ["-e", "print 'paused'; STDOUT.flush; sleep 0.2"])
      received = +""
      pty.pause
      pty.on_data { |data| received << data }

      sleep 0.15
      expect(received).to eq("")

      pty.resume
      wait_until { received.include?("paused") || pty.exit_status }
      pty.close

      expect(received).to include("paused")
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

    it "is idempotent" do
      pty = described_class.new(command: "/bin/cat")

      expect(pty.close).to be true
      expect { pty.close }.not_to raise_error
      expect(pty.close).to be false
      expect(pty.closed?).to be true
      expect(pty.write("ignored\n")).to be false
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

    it "stores exit status and calls late exit callbacks immediately" do
      pty = described_class.new(command: RbConfig.ruby, args: ["-e", "exit 7"])

      pty.wait_for_exit(2)
      late_code = nil
      pty.on_exit { |code| late_code = code }
      pty.close

      expect(pty.exit_status).to eq(7)
      expect(late_code).to eq(7)
      expect(pty.alive?).to be false
    end
  end

  def wait_until(timeout: 2.0)
    deadline = Time.now + timeout
    until yield
      raise "timed out waiting for PTY condition" if Time.now >= deadline

      sleep 0.01
    end
  end
end
