# frozen_string_literal: true

require 'securerandom'
require 'set'
require_relative "../common/event_emitter"
require_relative "../pty/pty"
require_relative "../terminal_options"

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
                     max_message_bytes: nil, rate_limit: nil, heartbeat_timeout: nil,
                     attach_policy: :multiple,
                     clock: -> { Time.now })
        @sessions = {}
        @max_sessions = max_sessions
        @default_command = default_command
        @terminal_options = symbolize_keys(terminal_options || {})
        @session_timeout = session_timeout
        @idle_timeout = idle_timeout
        @authenticator = authenticator
        @output_queue_limit = output_queue_limit
        @auto_flush_output = auto_flush_output
        @max_message_bytes = max_message_bytes
        @rate_limit = normalize_rate_limit(rate_limit)
        @heartbeat_timeout = heartbeat_timeout
        @attach_policy = attach_policy.to_sym
        @clock = clock
        @output_callbacks = []
        @exit_callbacks = []
        @message_history = Hash.new { |hash, key| hash[key] = [] }
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
        session_options = @terminal_options.merge(symbolize_keys(options))
        terminal_options = terminal_options_from(session_options)
        cols = terminal_options.fetch(:cols, 80)
        rows = terminal_options.fetch(:rows, 24)

        terminal = RTerm::Terminal.new(terminal_options)
        pty = create_pty(session_options, cols, rows)
        wire_pty(session_id, terminal, pty) if pty
        @sessions[session_id] = {
          terminal: terminal,
          pty: pty,
          created_at: now,
          last_activity_at: now,
          last_heartbeat_at: now,
          clients: Set.new,
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

      # Attaches a browser client to an existing session.
      # @param session_id [String]
      # @param client_id [String, nil]
      # @return [Hash] resumable session snapshot
      def attach_session(session_id, client_id: nil)
        session = get_session(session_id)
        client_id = (client_id || SecureRandom.uuid).to_s
        attach_client(session, client_id)
        touch(session)
        session_snapshot(session, client_id)
      end

      # Detaches a browser client from a session.
      # @param session_id [String]
      # @param client_id [String]
      def detach_session(session_id, client_id:)
        session = get_session(session_id)
        session[:clients].delete(client_id.to_s)
        touch(session)
      end

      # Re-attaches to an existing session and returns a lightweight state snapshot.
      # @param session_id [String]
      # @param client_id [String, nil]
      # @return [Hash]
      def resume_session(session_id, client_id: nil)
        session = get_session(session_id)
        heartbeat(session_id)
        attach_session(session_id, client_id: client_id)
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
      # @return [RTerm::Common::Disposable]
      def on_output(&block)
        raise ArgumentError, "on_output requires a block" unless block

        @output_callbacks << block
        RTerm::Common::Disposable.new { @output_callbacks.delete(block) }
      end

      # Registers a callback for PTY exit.
      # @yield [session_id, code]
      # @return [RTerm::Common::Disposable]
      def on_exit(&block)
        raise ArgumentError, "on_exit requires a block" unless block

        @exit_callbacks << block
        RTerm::Common::Disposable.new { @exit_callbacks.delete(block) }
      end

      # Queues output and flushes it to subscribers unless backpressure is enabled.
      # @param session_id [String]
      # @param data [String]
      def queue_output(session_id, data)
        session = get_session(session_id)
        bytes = data.to_s.bytesize
        if session[:queued_output_bytes] + bytes > @output_queue_limit
          destroy_session(session_id)
          @exit_callbacks.dup.each { |callback| callback.call(session_id, nil) }
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
        return ProtocolHandler.error("Unauthorized", code: "unauthorized") unless authorized?(message)
        return ProtocolHandler.error("Message too large", code: "message_too_large") if message_too_large?(message)
        return ProtocolHandler.error("Rate limit exceeded", code: "rate_limited") if rate_limited?(message)

        cleanup_expired
        case message[:type]
        when ProtocolHandler::MessageType::CREATE_SESSION
          payload = message[:payload]
          session_id = create_session(
            command: payload['command'],
            args: payload['args'] || [],
            env: payload['env'] || {},
            cwd: payload['cwd'],
            cols: payload['cols'] || 80,
            rows: payload['rows'] || 24
          )
          ProtocolHandler.session_created(session_id)

        when ProtocolHandler::MessageType::ATTACH_SESSION
          payload = message[:payload]
          snapshot = attach_session(message[:session_id], client_id: payload['client_id'])
          ProtocolHandler.session_attached(message[:session_id], snapshot)

        when ProtocolHandler::MessageType::DETACH_SESSION
          payload = message[:payload]
          detach_session(message[:session_id], client_id: payload['client_id'])
          ProtocolHandler.session_detached(message[:session_id])

        when ProtocolHandler::MessageType::RESUME_SESSION
          payload = message[:payload]
          snapshot = resume_session(message[:session_id], client_id: payload['client_id'])
          ProtocolHandler.session_resumed(message[:session_id], snapshot)

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
          heartbeat(message[:session_id]) if message[:session_id]
          ProtocolHandler.pong

        else
          ProtocolHandler.error("Unknown message type: #{message[:type]}", code: "unknown_message_type")
        end
      rescue SessionError => e
        ProtocolHandler.error(e.message, session_id: message[:session_id], code: "session_error")
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

      # @param session_id [String]
      # @return [Array<String>]
      def attached_clients(session_id)
        get_session(session_id)[:clients].to_a
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
        return true if @heartbeat_timeout && current - session[:last_heartbeat_at] > @heartbeat_timeout

        false
      end

      def heartbeat(session_id)
        session = get_session(session_id)
        session[:last_heartbeat_at] = now
        touch(session)
      end

      def normalize_rate_limit(rate_limit)
        return nil unless rate_limit

        config = symbolize_keys(rate_limit)
        limit = config[:limit] || config[:max_messages]
        interval = config[:interval]

        if limit.nil? || interval.nil?
          raise ArgumentError, "rate_limit requires :limit and :interval"
        end

        normalized = {
          limit: Integer(limit),
          interval: Float(interval)
        }

        if normalized[:limit] <= 0 || normalized[:interval] <= 0
          raise ArgumentError, "rate_limit :limit and :interval must be greater than 0"
        end

        normalized
      rescue TypeError, ArgumentError => e
        raise e if e.message.include?("rate_limit")

        raise ArgumentError, "rate_limit requires numeric :limit and :interval"
      end

      def symbolize_keys(hash)
        source = hash.respond_to?(:to_h) ? hash.to_h : hash
        source.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value
        end
      end

      def terminal_options_from(session_options)
        allowed = RTerm::TerminalOptions::DEFAULTS.keys
        session_options.select { |key, _value| allowed.include?(key.to_sym) }
      end

      def attach_client(session, client_id)
        client_id = client_id.to_s
        case @attach_policy
        when :single
          if !session[:clients].empty? && !session[:clients].include?(client_id)
            raise SessionError, "Session already has an attached client"
          end
        when :replace
          session[:clients].clear unless session[:clients].include?(client_id)
        when :multiple
          # Multiple clients may observe and drive the same terminal session.
        else
          raise SessionError, "Unknown attach policy: #{@attach_policy}"
        end

        session[:clients] << client_id
      end

      def session_snapshot(session, client_id)
        terminal = session[:terminal]
        {
          'client_id' => client_id,
          'cols' => terminal.cols,
          'rows' => terminal.rows,
          'title' => terminal.title,
          'icon_name' => terminal.icon_name,
          'modes' => terminal.modes,
          'images' => terminal.images
        }
      end

      def message_too_large?(message)
        return false unless @max_message_bytes

        message.to_s.bytesize > @max_message_bytes
      end

      def rate_limited?(message)
        return false unless @rate_limit

        limit = @rate_limit.fetch(:limit)
        interval = @rate_limit.fetch(:interval)
        key = message[:session_id] || :global
        current = now
        history = @message_history[key]
        history.reject! { |timestamp| current - timestamp > interval }
        return true if history.length >= limit

        history << current
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
          @output_callbacks.dup.each { |callback| callback.call(session_id, data) }
        end
      end

      def create_pty(options, cols, rows)
        command = options.key?(:command) ? options[:command] : @default_command
        return nil if command.nil? || command.empty?

        RTerm::Pty.new(
          command: command,
          args: options.fetch(:args, []),
          env: options.fetch(:env, {}),
          cwd: options[:cwd],
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
          @exit_callbacks.dup.each { |callback| callback.call(session_id, code) }
        end
      end
    end

    class SessionError < StandardError; end
  end
end
