# frozen_string_literal: true

require "open3"
require_relative "../../common/event_emitter"

module RTerm
  class ConPTY
    class ProcessBackend
      DEFAULT_READ_CHUNK_SIZE = 16 * 1024

      attr_reader :pid, :exit_status, :exit_signal, :cols, :rows

      def initialize(command: nil, args: [], env: {}, cwd: nil, cols: 80, rows: 24,
                     read_chunk_size: DEFAULT_READ_CHUNK_SIZE, **_options)
        @command = command || ENV["COMSPEC"] || "cmd.exe"
        @args = Array(args)
        @env = stringify_env(env || {})
        @cwd = cwd
        @cols = cols.to_i
        @rows = rows.to_i
        @read_chunk_size = [read_chunk_size.to_i, 1].max
        @on_data_callbacks = []
        @on_exit_callbacks = []
        @paused = false
        @closed = false
        @exit_status = nil
        @exit_signal = nil
        @exit_notified = false
        @mutex = Mutex.new
        spawn_process
      end

      def write(data)
        return false if closed?

        @stdin.write(data.to_s)
        @stdin.flush
        true
      rescue IOError, Errno::EPIPE
        false
      end

      def read
        return nil if closed?

        data = @stdout.read_nonblock(@read_chunk_size)
        data.force_encoding("UTF-8")
        data
      rescue IO::WaitReadable
        nil
      rescue EOFError, IOError
        record_exit_if_done
        nil
      end

      def close_stdin
        return false if closed? || @stdin.closed?

        @stdin.close
        true
      rescue IOError
        false
      end

      def pause
        @paused = true
      end

      def resume
        @paused = false
      end

      def paused?
        @paused
      end

      def on_data(&block)
        raise ArgumentError, "data callback block is required" unless block

        @on_data_callbacks << block
        start_read_thread
        Common::Disposable.new { @on_data_callbacks.delete(block) }
      end

      def on_exit(&block)
        raise ArgumentError, "exit callback block is required" unless block

        if exited?
          block.call(@exit_status)
          return Common::Disposable.new {}
        end

        @on_exit_callbacks << block
        Common::Disposable.new { @on_exit_callbacks.delete(block) }
      end

      def resize(cols, rows)
        @cols = cols.to_i
        @rows = rows.to_i
        true
      end

      def kill(signal = :TERM, group: false)
        target = group ? -@pid : @pid
        Process.kill(signal, target)
        true
      rescue Errno::ESRCH, Errno::ECHILD, Errno::EPERM
        false
      end

      def close(timeout: 1.0)
        return false if closed?

        @closed = true
        @stdin.close rescue nil
        @stdout.close rescue nil
        unless exited?
          kill(:TERM)
          wait_for_exit(timeout)
        end
        true
      end

      def wait_for_exit(timeout = nil)
        return @exit_status if exited?

        @wait_thread.join(timeout)
        record_exit_if_done
        @exit_status
      end

      def alive?
        return false if exited?

        @wait_thread.alive?
      end

      def closed?
        @closed
      end

      def process_group_enabled?
        false
      end

      def process_group_id
        nil
      end

      def process_group_fallback_reason
        nil
      end

      private

      def spawn_process
        options = {}
        options[:chdir] = @cwd if @cwd
        @stdin, @stdout, @wait_thread = Open3.popen2e(@env, @command, *@args, options)
        @pid = @wait_thread.pid
      end

      def start_read_thread
        return if @read_thread&.alive?

        @read_thread = Thread.new do
          loop do
            break if closed? || @stdout.closed?

            if paused?
              sleep 0.05
              next
            end

            data = @stdout.read_nonblock(@read_chunk_size)
            data.force_encoding("UTF-8")
            @on_data_callbacks.dup.each { |callback| callback.call(data) }
          rescue IO::WaitReadable
            break if closed? || @stdout.closed?

            IO.select([@stdout], nil, nil, 0.1) rescue nil
            retry
          rescue EOFError, IOError, Errno::EBADF
            break
          end

          wait_for_exit(1.0)
        end
      end

      def exited?
        !@exit_status.nil? || !@exit_signal.nil?
      end

      def record_exit_if_done
        return @exit_status if exited?
        return nil if @wait_thread.alive?

        status = @wait_thread.value
        callbacks = nil
        @mutex.synchronize do
          return @exit_status if exited?

          @exit_status = status.exitstatus
          @exit_signal = status.termsig
          unless @exit_notified
            @exit_notified = true
            callbacks = @on_exit_callbacks.dup
          end
        end
        callbacks&.each { |callback| callback.call(@exit_status) }
        @exit_status
      end

      def stringify_env(env)
        env.each_with_object({}) do |(key, value), result|
          result[key.to_s] = value.to_s
        end
      end
    end
  end
end
