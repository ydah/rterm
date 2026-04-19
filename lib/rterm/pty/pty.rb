# frozen_string_literal: true

require 'pty'
require 'io/console'
require_relative "../common/event_emitter"

module RTerm
  class Pty
    DEFAULT_READ_CHUNK_SIZE = 16 * 1024

    attr_reader :pid, :exit_status

    # @param command [String] command to run (default: ENV['SHELL'] || '/bin/bash')
    # @param args [Array<String>] command arguments
    # @param env [Hash] environment variables
    # @param cwd [String, nil] working directory for the child process
    # @param cols [Integer] terminal columns
    # @param rows [Integer] terminal rows
    # @param read_chunk_size [Integer] maximum bytes read from the PTY per read
    def initialize(command: nil, args: [], env: {}, cwd: nil, cols: 80, rows: 24,
                   read_chunk_size: DEFAULT_READ_CHUNK_SIZE)
      cmd = command || ENV['SHELL'] || '/bin/bash'
      spawn_args = build_spawn_args(cmd, args, env, cwd)
      @master, @slave, @pid = ::PTY.spawn(*spawn_args)
      @master.winsize = [rows, cols]
      @read_chunk_size = [read_chunk_size.to_i, 1].max
      @on_data_callbacks = []
      @on_exit_callbacks = []
      @read_thread = nil
      @exit_status = nil
      @process_status = nil
      @exit_notified = false
      @closed = false
      @stdin_closed = false
      @paused = false
      @mutex = Mutex.new
    end

    # Write data to the PTY
    def write(data)
      return false if closed?

      @slave.write(data)
      true
    rescue Errno::EIO, IOError
      false
    end

    # Close the child's stdin side.
    # @return [Boolean]
    def close_stdin
      return false if closed? || @stdin_closed || @slave.closed?

      @slave.write("\x04")
      @stdin_closed = true
      true
    rescue Errno::EIO, IOError
      false
    end

    # Pause the background read loop.
    def pause
      @paused = true
      true
    end

    # Resume the background read loop.
    def resume
      @paused = false
      true
    end

    # @return [Boolean]
    def paused?
      @paused
    end

    # Read available PTY output without blocking.
    # @return [String, nil]
    def read
      return nil if closed?

      data = @master.read_nonblock(@read_chunk_size)
      data.force_encoding('UTF-8')
      data
    rescue IO::WaitReadable
      nil
    rescue EOFError, Errno::EIO, IOError
      reap_child(nonblock: true)
      nil
    end

    # Register callback for data received from PTY
    def on_data(&block)
      raise ArgumentError, "data callback block is required" unless block

      @on_data_callbacks << block
      start_read_thread unless @read_thread&.alive?
      Common::Disposable.new { @on_data_callbacks.delete(block) }
    end

    # Register callback for process exit
    def on_exit(&block)
      raise ArgumentError, "exit callback block is required" unless block

      if exited?
        block.call(@exit_status)
        return Common::Disposable.new {}
      end

      @on_exit_callbacks << block
      Common::Disposable.new { @on_exit_callbacks.delete(block) }
    end

    # Resize the PTY
    def resize(cols, rows)
      return false if closed?

      @master.winsize = [rows, cols]
      Process.kill(:WINCH, @pid) rescue nil
      true
    rescue Errno::EIO, IOError
      false
    end

    # Send signal to child process
    def kill(signal = :TERM)
      Process.kill(signal, @pid)
      true
    rescue Errno::ESRCH, Errno::ECHILD
      false
    end

    # Close the PTY and clean up
    def close(timeout: 1.0)
      return false if closed?

      @closed = true
      @master.close rescue nil
      @slave.close rescue nil
      join_read_thread(timeout)

      unless exited?
        kill(:TERM)
        wait_for_exit(timeout)
      end

      true
    end

    # @return [Boolean] whether the PTY has been closed
    def closed?
      @closed
    end

    # Waits for the child process to exit.
    # @param timeout [Float, nil] seconds to wait, nil waits indefinitely
    # @return [Integer, nil] exit code or nil on timeout/signal-only exit
    def wait_for_exit(timeout = nil)
      deadline = timeout ? Time.now + timeout : nil

      loop do
        return @exit_status if exited?

        status = reap_child(nonblock: true)
        return status if status || exited?
        return nil if deadline && Time.now >= deadline

        sleep 0.01
      end
    end

    # Check if child process is alive
    def alive?
      return false if exited?

      Process.kill(0, @pid)
      true
    rescue Errno::ESRCH, Errno::ECHILD
      false
    end

    private

    def start_read_thread
      @read_thread = Thread.new do
        loop do
          break if closed? || @master.closed?

          if paused?
            sleep 0.05
            next
          end

          data = @master.read_nonblock(@read_chunk_size)
          data.force_encoding('UTF-8')
          @on_data_callbacks.dup.each { |cb| cb.call(data) }
        rescue IO::WaitReadable
          break if closed? || @master.closed?

          begin
            IO.select([@master], nil, nil, 0.1)
          rescue IOError, Errno::EBADF
            break
          end
          retry
        rescue EOFError, Errno::EIO, IOError, Errno::EBADF
          break
        end

        wait_for_exit(1.0)
      end
    end

    def join_read_thread(timeout)
      return unless @read_thread
      return if @read_thread == Thread.current

      @read_thread.join(timeout)
      return unless @read_thread.alive?

      @read_thread.kill
      @read_thread.join(0.1)
    end

    def exited?
      !@process_status.nil?
    end

    def reap_child(nonblock:)
      return @exit_status if exited?

      flags = nonblock ? Process::WNOHANG : 0
      result = Process.wait2(@pid, flags)
      return nil unless result

      record_exit(result[1])
    rescue Errno::ECHILD
      notify_exit(@exit_status) if exited?
      @exit_status
    end

    def record_exit(status)
      callbacks = nil
      code = status.exitstatus

      @mutex.synchronize do
        return @exit_status if @process_status

        @process_status = status
        @exit_status = code
        unless @exit_notified
          @exit_notified = true
          callbacks = @on_exit_callbacks.dup
        end
      end

      callbacks&.each { |cb| cb.call(code) }
      code
    end

    def notify_exit(code)
      callbacks = nil
      @mutex.synchronize do
        return if @exit_notified

        @exit_notified = true
        callbacks = @on_exit_callbacks.dup
      end

      callbacks&.each { |cb| cb.call(code) }
    end

    def stringify_env(env)
      env.each_with_object({}) do |(key, value), result|
        result[key.to_s] = value.to_s
      end
    end

    def build_spawn_args(cmd, args, env, cwd)
      spawn_args = []
      spawn_args << stringify_env(env) unless env.empty?
      spawn_args << cmd
      spawn_args.concat(args)
      spawn_args << { chdir: cwd } if cwd
      spawn_args
    end
  end

  PTY = Pty unless const_defined?(:PTY, false)
end
