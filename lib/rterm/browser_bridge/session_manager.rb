# frozen_string_literal: true

require 'securerandom'
require_relative "../pty/pty"

module RTerm
  module BrowserBridge
    # Manages multiple terminal sessions.
    # Each session has a unique ID, a Terminal instance, and optionally a PTY.
    class SessionManager
      attr_reader :max_sessions

      # @param max_sessions [Integer] maximum number of concurrent sessions
      def initialize(max_sessions: 10, default_command: nil, terminal_options: {},
                     session_timeout: nil, idle_timeout: nil, authenticator: nil,
                     output_queue_limit: 1_048_576, auto_flush_output: true,
                     clock: -> { Time.now })
        @sessions = {}
        @max_sessions = max_sessions
        @default_command = default_command
        @terminal_options = terminal_options
        @session_timeout = session_timeout
        @idle_timeout = idle_timeout
        @authenticator = authenticator
        @output_queue_limit = output_queue_limit
        @auto_flush_output = auto_flush_output
        @clock = clock
        @output_callbacks = []
        @exit_callbacks = []
      end

      # Creates a new terminal session.
      # @param options [Hash] session options
      # @option options [String] :command command to run
      # @option options [Array<String>] :args command arguments
      # @option options [Hash] :env environment variables
      # @option options [Integer] :cols terminal columns
      # @option options [Integer] :rows terminal rows
      # @return [String] session ID
      # @raise [SessionError] if max sessions reached
      def create_session(options = {})
        raise SessionError, "Maximum sessions (#{@max_sessions}) reached" if @sessions.size >= @max_sessions

        session_id = SecureRandom.uuid
        session_options = @terminal_options.merge(options)
        cols = session_options.fetch(:cols, 80)
        rows = session_options.fetch(:rows, 24)

        terminal = RTerm::Terminal.new(cols: cols, rows: rows)
        pty = create_pty(session_options, cols, rows)
        wire_pty(session_id, terminal, pty) if pty
        @sessions[session_id] = {
          terminal: terminal,
          pty: pty,
          created_at: now,
          last_activity_at: now,
          output_queue: [],
          queued_output_bytes: 0
        }

        session_id
      end

      # Destroys a session.
      # @param session_id [String]
      # @raise [SessionError] if session not found
      def destroy_session(session_id)
        session = @sessions.delete(session_id)
        raise SessionError, "Session not found: #{session_id}" unless session

        session[:pty]&.close
        session[:terminal].dispose
      end

      # Returns the terminal for a session.
      # @param session_id [String]
      # @return [RTerm::Terminal]
      # @raise [SessionError] if session not found
      def get_terminal(session_id)
        get_session(session_id)[:terminal]
      end

      # Writes input data to a session's terminal.
      # @param session_id [String]
      # @param data [String]
      def write(session_id, data)
        session = get_session(session_id)
        touch(session)
        if session[:pty]
          session[:terminal].input(data)
        else
          session[:terminal].write(data)
        end
      end

      # Resizes a session's terminal.
      # @param session_id [String]
      # @param cols [Integer]
      # @param rows [Integer]
      def resize(session_id, cols, rows)
        session = get_session(session_id)
        touch(session)
        session[:terminal].resize(cols, rows)
        session[:pty]&.resize(cols, rows)
      end

      # Registers a callback for PTY output.
      # @yield [session_id, data]
      def on_output(&block)
        @output_callbacks << block
      end

      # Registers a callback for PTY exit.
      # @yield [session_id, code]
      def on_exit(&block)
        @exit_callbacks << block
      end

      # Queues output and flushes it to subscribers unless backpressure is enabled.
      # @param session_id [String]
      # @param data [String]
      def queue_output(session_id, data)
        session = get_session(session_id)
        bytes = data.to_s.bytesize
        if session[:queued_output_bytes] + bytes > @output_queue_limit
          destroy_session(session_id)
          @exit_callbacks.each { |callback| callback.call(session_id, nil) }
          return
        end

        session[:output_queue] << data
        session[:queued_output_bytes] += bytes
        flush_output(session_id) if @auto_flush_output
      end

      # Flushes queued output to subscribers.
      # @param session_id [String, nil]
      def flush_output(session_id = nil)
        ids = session_id ? [session_id] : session_ids
        ids.each { |id| flush_session_output(id) }
      end

      # @param session_id [String]
      # @return [Integer]
      def pending_output_bytes(session_id)
        get_session(session_id)[:queued_output_bytes]
      end

      # Destroys expired or idle sessions.
      # @return [Array<String>] destroyed session IDs
      def cleanup_expired
        expired = @sessions.select { |_id, session| expired?(session) }.keys
        expired.each { |session_id| destroy_session(session_id) }
        expired
      end

      # Processes an incoming protocol message.
      # @param message [Hash] decoded protocol message
      # @return [String, nil] response message (JSON) or nil
      def process_message(message)
        return ProtocolHandler.error("Unauthorized") unless authorized?(message)

        cleanup_expired
        case message[:type]
        when ProtocolHandler::MessageType::CREATE_SESSION
          payload = message[:payload]
          session_id = create_session(
            command: payload['command'],
            args: payload['args'] || [],
            env: payload['env'] || {},
            cols: payload['cols'] || 80,
            rows: payload['rows'] || 24
          )
          ProtocolHandler.session_created(session_id)

        when ProtocolHandler::MessageType::DESTROY_SESSION
          destroy_session(message[:session_id])
          ProtocolHandler.session_destroyed(message[:session_id])

        when ProtocolHandler::MessageType::INPUT
          write(message[:session_id], message[:payload]['data'])
          nil

        when ProtocolHandler::MessageType::RESIZE
          resize(
            message[:session_id],
            message[:payload]['cols'],
            message[:payload]['rows']
          )
          nil

        when ProtocolHandler::MessageType::PING
          ProtocolHandler.pong

        else
          ProtocolHandler.error("Unknown message type: #{message[:type]}")
        end
      rescue SessionError => e
        ProtocolHandler.error(e.message, session_id: message[:session_id])
      end

      # @return [Integer] current number of active sessions
      def session_count
        @sessions.size
      end

      # @param session_id [String]
      # @return [Boolean]
      def session_exists?(session_id)
        @sessions.key?(session_id)
      end

      # Returns all session IDs
      # @return [Array<String>]
      def session_ids
        @sessions.keys
      end

      private

      def get_session(session_id)
        session = @sessions[session_id]
        raise SessionError, "Session not found: #{session_id}" unless session

        session
      end

      def now
        @clock.call
      end

      def touch(session)
        session[:last_activity_at] = now
      end

      def expired?(session)
        current = now
        return true if @session_timeout && current - session[:created_at] > @session_timeout
        return true if @idle_timeout && current - session[:last_activity_at] > @idle_timeout

        false
      end

      def authorized?(message)
        return true unless @authenticator

        @authenticator.call(message) == true
      end

      def flush_session_output(session_id)
        session = get_session(session_id)
        until session[:output_queue].empty?
          data = session[:output_queue].shift
          session[:queued_output_bytes] -= data.to_s.bytesize
          @output_callbacks.each { |callback| callback.call(session_id, data) }
        end
      end

      def create_pty(options, cols, rows)
        command = options.key?(:command) ? options[:command] : @default_command
        return nil if command.nil? || command.empty?

        RTerm::Pty.new(
          command: command,
          args: options.fetch(:args, []),
          env: options.fetch(:env, {}),
          cols: cols,
          rows: rows
        )
      end

      def wire_pty(session_id, terminal, pty)
        terminal.on(:data) { |data| pty.write(data) }
        pty.on_data do |data|
          terminal.write(data)
          queue_output(session_id, data) if session_exists?(session_id)
        end
        pty.on_exit do |code|
          session = @sessions.delete(session_id)
          session[:terminal].dispose if session
          @exit_callbacks.each { |callback| callback.call(session_id, code) }
        end
      end
    end

    class SessionError < StandardError; end
  end
end
