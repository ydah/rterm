# frozen_string_literal: true

require 'securerandom'

module RTerm
  module BrowserBridge
    # Manages multiple terminal sessions.
    # Each session has a unique ID, a Terminal instance, and optionally a PTY.
    class SessionManager
      attr_reader :max_sessions

      # @param max_sessions [Integer] maximum number of concurrent sessions
      def initialize(max_sessions: 10)
        @sessions = {}
        @max_sessions = max_sessions
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
        cols = options.fetch(:cols, 80)
        rows = options.fetch(:rows, 24)

        terminal = RTerm::Terminal.new(cols: cols, rows: rows)
        @sessions[session_id] = {
          terminal: terminal,
          created_at: Time.now
        }

        session_id
      end

      # Destroys a session.
      # @param session_id [String]
      # @raise [SessionError] if session not found
      def destroy_session(session_id)
        session = @sessions.delete(session_id)
        raise SessionError, "Session not found: #{session_id}" unless session

        session[:terminal].dispose
      end

      # Returns the terminal for a session.
      # @param session_id [String]
      # @return [RTerm::Terminal]
      # @raise [SessionError] if session not found
      def get_terminal(session_id)
        session = @sessions[session_id]
        raise SessionError, "Session not found: #{session_id}" unless session

        session[:terminal]
      end

      # Writes input data to a session's terminal.
      # @param session_id [String]
      # @param data [String]
      def write(session_id, data)
        get_terminal(session_id).write(data)
      end

      # Resizes a session's terminal.
      # @param session_id [String]
      # @param cols [Integer]
      # @param rows [Integer]
      def resize(session_id, cols, rows)
        get_terminal(session_id).resize(cols, rows)
      end

      # Processes an incoming protocol message.
      # @param message [Hash] decoded protocol message
      # @return [String, nil] response message (JSON) or nil
      def process_message(message)
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
    end

    class SessionError < StandardError; end
  end
end
