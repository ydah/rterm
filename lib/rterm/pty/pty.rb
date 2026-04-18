# frozen_string_literal: true

require 'pty'
require 'io/console'

module RTerm
  class Pty
    attr_reader :pid

    # @param command [String] command to run (default: ENV['SHELL'] || '/bin/bash')
    # @param args [Array<String>] command arguments
    # @param env [Hash] environment variables
    # @param cols [Integer] terminal columns
    # @param rows [Integer] terminal rows
    def initialize(command: nil, args: [], env: {}, cols: 80, rows: 24)
      cmd = command || ENV['SHELL'] || '/bin/bash'
      spawn_args = env.empty? ? [cmd, *args] : [stringify_env(env), cmd, *args]
      @master, @slave, @pid = ::PTY.spawn(*spawn_args)
      @master.winsize = [rows, cols]
      @on_data_callbacks = []
      @on_exit_callbacks = []
      @read_thread = nil
    end

    # Write data to the PTY
    def write(data)
      @slave.write(data)
    end

    # Read available PTY output without blocking.
    # @return [String, nil]
    def read
      data = @master.read_nonblock(4096)
      data.force_encoding('UTF-8')
      data
    rescue IO::WaitReadable
      nil
    rescue EOFError, Errno::EIO
      nil
    end

    # Register callback for data received from PTY
    def on_data(&block)
      @on_data_callbacks << block
      start_read_thread unless @read_thread&.alive?
    end

    # Register callback for process exit
    def on_exit(&block)
      @on_exit_callbacks << block
    end

    # Resize the PTY
    def resize(cols, rows)
      @master.winsize = [rows, cols]
      Process.kill(:WINCH, @pid) rescue nil
    end

    # Send signal to child process
    def kill(signal = :TERM)
      Process.kill(signal, @pid) rescue nil
    end

    # Close the PTY and clean up
    def close
      @read_thread&.kill
      @master.close rescue nil
      @slave.close rescue nil
      Process.wait(@pid) rescue nil
    end

    # Check if child process is alive
    def alive?
      Process.kill(0, @pid)
      true
    rescue Errno::ESRCH
      false
    end

    private

    def start_read_thread
      @read_thread = Thread.new do
        loop do
          break if @master.closed?
          data = @master.read_nonblock(4096)
          data.force_encoding('UTF-8')
          @on_data_callbacks.each { |cb| cb.call(data) }
        rescue IO::WaitReadable
          IO.select([@master], nil, nil, 0.1)
          retry
        rescue EOFError, Errno::EIO
          break
        end
        exit_status = Process.wait2(@pid) rescue nil
        code = exit_status ? exit_status[1].exitstatus : nil
        @on_exit_callbacks.each { |cb| cb.call(code) }
      end
    end

    def stringify_env(env)
      env.each_with_object({}) do |(key, value), result|
        result[key.to_s] = value.to_s
      end
    end
  end

  PTY = Pty unless const_defined?(:PTY, false)
end
