# frozen_string_literal: true

module RTerm
  # Boundary for a Windows ConPTY-backed PTY adapter.
  class ConPTY
    class UnsupportedPlatformError < StandardError; end
    class BackendUnavailableError < StandardError; end

    class << self
      attr_accessor :backend_factory
    end

    attr_reader :backend, :options

    # @return [Boolean]
    def self.supported?
      Gem.win_platform?
    end

    # @return [Boolean]
    def self.available?
      supported? && backend_factory.respond_to?(:call)
    end

    def self.configure_backend(factory = nil, &block)
      self.backend_factory = block || factory
    end

    def initialize(*positional, backend: nil, backend_factory: nil, **options)
      raise ArgumentError, "positional arguments are not supported" unless positional.empty?

      @options = options.dup
      @backend = backend || build_backend(backend_factory)
    end

    def write(data)
      backend.write(data)
    end

    def read
      backend.read if backend.respond_to?(:read)
    end

    def close_stdin
      return false unless backend.respond_to?(:close_stdin)

      backend.close_stdin
    end

    def pause
      return false unless backend.respond_to?(:pause)

      backend.pause
    end

    def resume
      return false unless backend.respond_to?(:resume)

      backend.resume
    end

    def paused?
      backend.respond_to?(:paused?) && backend.paused?
    end

    def on_data(&block)
      raise ArgumentError, "data callback block is required" unless block

      backend.on_data(&block)
    end

    def on_exit(&block)
      raise ArgumentError, "exit callback block is required" unless block

      backend.on_exit(&block)
    end

    def resize(cols, rows)
      backend.resize(cols, rows)
    end

    def kill(signal = :TERM, group: false)
      return false unless backend.respond_to?(:kill)

      backend.kill(signal, group: group)
    end

    def close(timeout: 1.0)
      backend.close(timeout: timeout)
    end

    def wait_for_exit(timeout = nil)
      backend.wait_for_exit(timeout)
    end

    def alive?
      backend.alive?
    end

    def closed?
      backend.respond_to?(:closed?) && backend.closed?
    end

    def pid
      backend.pid if backend.respond_to?(:pid)
    end

    def exit_status
      backend.exit_status if backend.respond_to?(:exit_status)
    end

    def exit_signal
      backend.exit_signal if backend.respond_to?(:exit_signal)
    end

    def process_group_id
      backend.process_group_id if backend.respond_to?(:process_group_id)
    end

    def process_group_enabled?
      backend.respond_to?(:process_group_enabled?) && backend.process_group_enabled?
    end

    def process_group_fallback_reason
      backend.process_group_fallback_reason if backend.respond_to?(:process_group_fallback_reason)
    end

    private

    def build_backend(factory)
      unless self.class.supported?
        raise UnsupportedPlatformError, "RTerm::ConPTY is only available on Windows"
      end

      callable = factory || self.class.backend_factory
      unless callable.respond_to?(:call)
        raise BackendUnavailableError, "RTerm::ConPTY requires a backend factory"
      end

      callable.call(**@options)
    end
  end
end
