# frozen_string_literal: true

require_relative "conpty/process_backend"

module RTerm
  # Boundary for a Windows ConPTY-backed PTY adapter.
  class ConPTY
    class UnsupportedPlatformError < StandardError; end
    class BackendUnavailableError < StandardError; end

    REQUIRED_BACKEND_METHODS = %i[
      write
      on_data
      on_exit
      resize
      close
      wait_for_exit
      alive?
    ].freeze
    OPTIONAL_BACKEND_METHODS = %i[
      read
      close_stdin
      pause
      resume
      paused?
      kill
      closed?
      pid
      exit_status
      exit_signal
      native?
      process_group_id
      process_group_enabled?
      process_group_fallback_reason
    ].freeze

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
      supported?
    end

    def self.configure_backend(factory = nil, &block)
      self.backend_factory = block || factory
    end

    def self.backend_contract
      {
        required: REQUIRED_BACKEND_METHODS,
        optional: OPTIONAL_BACKEND_METHODS
      }
    end

    def initialize(*positional, backend: nil, backend_factory: nil, **options)
      raise ArgumentError, "positional arguments are not supported" unless positional.empty?

      @options = options.dup
      @backend = validate_backend!(backend || build_backend(backend_factory))
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

    def native?
      backend.respond_to?(:native?) && backend.native?
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
      return callable.call(**@options) if callable.respond_to?(:call)

      ProcessBackend.new(**@options)
    end

    def validate_backend!(candidate)
      missing = REQUIRED_BACKEND_METHODS.reject { |method_name| candidate.respond_to?(method_name) }
      return candidate if missing.empty?

      raise BackendUnavailableError, "RTerm::ConPTY backend is missing required methods: #{missing.join(', ')}"
    end
  end
end
