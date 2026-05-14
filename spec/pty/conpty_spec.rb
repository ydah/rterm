# frozen_string_literal: true

RSpec.describe RTerm::ConPTY do
  it "reports platform support" do
    expect(described_class.supported?).to eq(Gem.win_platform?)
  end

  it "raises a platform error outside Windows" do
    skip "ConPTY is only expected to raise this boundary error off Windows" if described_class.supported?

    expect { described_class.new(command: "cmd.exe") }
      .to raise_error(RTerm::ConPTY::UnsupportedPlatformError, /only available on Windows/)
  end

  it "forwards PTY operations to a supplied backend" do
    backend = Class.new do
      attr_reader :writes, :sizes

      def initialize
        @writes = []
        @sizes = []
        @closed = false
      end

      def write(data)
        @writes << data
        true
      end

      def on_data(&block)
        block.call("output")
        RTerm::Common::Disposable.new {}
      end

      def on_exit(&block)
        block.call(0)
        RTerm::Common::Disposable.new {}
      end

      def resize(cols, rows)
        @sizes << [cols, rows]
        true
      end

      def alive?
        !@closed
      end

      def close(timeout: 1.0)
        @closed = true
        timeout
      end

      def closed?
        @closed
      end

      def wait_for_exit(_timeout = nil)
        0
      end
    end.new
    data = []
    exits = []

    conpty = described_class.new(command: "cmd.exe", backend: backend)

    expect(conpty.write("dir\r")).to be true
    expect(conpty.on_data { |chunk| data << chunk }).to be_a(RTerm::Common::Disposable)
    expect(conpty.on_exit { |status| exits << status }).to be_a(RTerm::Common::Disposable)
    expect(conpty.resize(100, 40)).to be true
    expect(conpty.alive?).to be true
    expect(conpty.close(timeout: 0.2)).to eq(0.2)
    expect(conpty).to be_closed
    expect(conpty.wait_for_exit).to eq(0)
    expect(backend.writes).to eq(["dir\r"])
    expect(backend.sizes).to eq([[100, 40]])
    expect(data).to eq(["output"])
    expect(exits).to eq([0])
  end

  it "builds a backend from a factory when the platform is supported" do
    backend = Class.new do
      def write(_data)
        true
      end

      def on_data
        RTerm::Common::Disposable.new {}
      end

      def on_exit
        RTerm::Common::Disposable.new {}
      end

      def resize(_cols, _rows)
        true
      end

      def close(timeout: 1.0)
        timeout
      end

      def wait_for_exit(_timeout = nil)
        0
      end

      def alive?
        true
      end
    end.new
    received_options = nil

    allow(described_class).to receive(:supported?).and_return(true)
    conpty = described_class.new(command: "cmd.exe", cols: 120, backend_factory: lambda { |**options|
      received_options = options
      backend
    })

    expect(conpty.backend).to equal(backend)
    expect(conpty.options).to include(command: "cmd.exe", cols: 120)
    expect(received_options).to include(command: "cmd.exe", cols: 120)
  end

  it "uses the bundled process backend by default when the platform is supported" do
    backend = Class.new do
      def write(_data)
        true
      end

      def on_data
        RTerm::Common::Disposable.new {}
      end

      def on_exit
        RTerm::Common::Disposable.new {}
      end

      def resize(_cols, _rows)
        true
      end

      def close(timeout: 1.0)
        timeout
      end

      def wait_for_exit(_timeout = nil)
        0
      end

      def alive?
        true
      end
    end.new

    allow(described_class).to receive(:supported?).and_return(true)
    allow(RTerm::ConPTY::ProcessBackend).to receive(:new).with(command: "cmd.exe").and_return(backend)

    conpty = described_class.new(command: "cmd.exe")

    expect(conpty.backend).to equal(backend)
  end

  it "describes and validates the backend contract" do
    expect(described_class.backend_contract[:required]).to include(
      :write,
      :on_data,
      :on_exit,
      :resize,
      :close,
      :wait_for_exit,
      :alive?
    )

    expect { described_class.new(command: "cmd.exe", backend: Object.new) }
      .to raise_error(RTerm::ConPTY::BackendUnavailableError, /missing required methods/)
  end

  it "reports backend availability" do
    allow(described_class).to receive(:supported?).and_return(true)
    described_class.configure_backend(->(**_options) { Object.new })

    expect(described_class.available?).to be true
  ensure
    described_class.configure_backend(nil)
  end

  it "provides a process backend implementation" do
    backend = RTerm::ConPTY::ProcessBackend.new(
      command: Gem.ruby,
      args: ["-e", "STDOUT.write('ready'); STDOUT.flush"]
    )
    output = nil
    deadline = Time.now + 1

    until output || Time.now >= deadline
      output = backend.read
      sleep 0.01 unless output
    end

    expect(output).to eq("ready")
    expect(backend.resize(120, 40)).to be true
    expect(backend.cols).to eq(120)
    expect(backend.rows).to eq(40)
    expect(backend.wait_for_exit(1)).to eq(0)
  ensure
    backend&.close
  end
end
