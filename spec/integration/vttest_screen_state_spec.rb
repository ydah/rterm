# frozen_string_literal: true

RSpec.describe "vttest screen-state assertions" do
  it "captures the vttest menu into terminal buffer state when available" do
    vttest = command_path("vttest")
    skip "vttest not installed" unless vttest || ENV["CI"] || ENV["RTERM_STRICT_E2E"] == "1"
    raise "vttest not installed" unless vttest

    terminal = RTerm::Terminal.new(cols: 80, rows: 24)
    raw = +""
    pty = RTerm::Pty.new(command: vttest, env: { "TERM" => "xterm-256color" }, cols: 80, rows: 24)
    pty.on_data do |data|
      raw << data
      terminal.write(data)
    end

    wait_until(timeout: 2.0) { raw.match?(/VT|test/i) }
    pty.write("q")
    pty.close

    terminal.select_all
    expect(terminal.selection).to match(/VT|test/i)
  end

  def command_path(command)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
      path = File.join(directory, command)
      return path if File.executable?(path) && !File.directory?(path)
    end
    nil
  end

  def wait_until(timeout:)
    deadline = Time.now + timeout
    until yield
      break if Time.now >= deadline

      sleep 0.01
    end
  end
end
