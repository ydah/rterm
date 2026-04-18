# frozen_string_literal: true

RSpec.describe "PTY real application integration" do
  it "renders shell ANSI output through the terminal emulator" do
    shell = command_path("bash") || command_path("sh") || "/bin/sh"
    args = shell.end_with?("bash") ? ["--noprofile", "--norc", "-lc", ansi_command] : ["-lc", ansi_command]

    terminal, _raw, status = run_pty_app(shell, args)

    line = terminal.buffer.active.get_line(0)
    expect(status).to eq(0)
    expect(line.to_string).to include("red")
    expect(line.get_cell(0).fg_color_mode).to eq(:p16)
  end

  it "runs vim through a PTY when available" do
    vim = command_path("vim")
    skip "vim not installed" unless vim

    _terminal, _raw, status = run_pty_app(
      vim,
      ["-Nu", "NONE", "-n", "+set nomore", "+qa!"],
      timeout: 3.0
    )

    expect(status).to eq(0)
  end

  it "runs tmux through a PTY when available" do
    tmux = command_path("tmux")
    skip "tmux not installed" unless tmux

    socket = "rterm-test-#{Process.pid}-#{rand(10_000)}"
    _terminal, _raw, status = run_pty_app(
      tmux,
      ["-L", socket, "-f", "/dev/null", "new-session", "printf tmux-ready; sleep 0.1"],
      timeout: 5.0
    )

    expect(status).to eq(0)
  end

  it "starts vttest through a PTY when available" do
    vttest = command_path("vttest")
    skip "vttest not installed" unless vttest

    _terminal, raw, _status = run_pty_app(vttest, [], input: ["q"], timeout: 2.0)

    expect(raw).to match(/VT|test/i)
  end

  def ansi_command
    "printf '\\033[31mred\\033[0m\\n'; exit 0"
  end

  def run_pty_app(command, args, input: [], timeout: 2.0)
    terminal = RTerm::Terminal.new(cols: 80, rows: 24)
    raw = +""
    pty = RTerm::Pty.new(command: command, args: args, env: { "TERM" => "xterm-256color" }, cols: 80, rows: 24)
    pty.on_data do |data|
      raw << data
      terminal.write(data)
    end
    input.each { |chunk| pty.write(chunk) }

    wait_until(timeout: timeout) { pty.exit_status || raw.bytesize.positive? }
    wait_until(timeout: timeout) { pty.exit_status } unless input.any?
    pty.kill(:TERM) unless pty.exit_status
    pty.close

    [terminal, raw, pty.exit_status]
  end

  def wait_until(timeout:)
    deadline = Time.now + timeout
    until yield
      break if Time.now >= deadline

      sleep 0.01
    end
  end

  def command_path(command)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
      path = File.join(directory, command)
      return path if File.executable?(path) && !File.directory?(path)
    end
    nil
  end
end
