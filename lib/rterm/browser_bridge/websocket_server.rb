# frozen_string_literal: true

require_relative "protocol_handler"
require_relative "session_manager"

module RTerm
  module BrowserBridge
    # WebSocket entry point for browser-based xterm.js clients.
    class WebSocketServer
      Config = Struct.new(
        :default_command,
        :max_sessions,
        :terminal_options,
        :session_timeout,
        :idle_timeout,
        :authenticator,
        :output_queue_limit,
        keyword_init: true
      )

      class << self
        # @return [Config]
        def config
          @config ||= Config.new(
            default_command: nil,
            max_sessions: 10,
            terminal_options: {},
            session_timeout: nil,
            idle_timeout: nil,
            authenticator: nil,
            output_queue_limit: 1_048_576
          )
        end

        # @yield [Config]
        # @return [Config]
        def configure
          yield config
          @session_manager = nil
          config
        end

        # @return [SessionManager]
        def session_manager
          @session_manager ||= SessionManager.new(
            max_sessions: config.max_sessions,
            default_command: config.default_command,
            terminal_options: config.terminal_options,
            session_timeout: config.session_timeout,
            idle_timeout: config.idle_timeout,
            authenticator: config.authenticator,
            output_queue_limit: config.output_queue_limit
          )
        end

        # Handles a Rack environment with faye-websocket when available.
        # @param env [Hash]
        # @return [Object]
        def handle(env)
          faye = load_faye_websocket
          raise LoadError, "Install faye-websocket to use RTerm::BrowserBridge::WebSocketServer" unless faye
          raise ProtocolError, "Request is not a WebSocket upgrade" unless faye.websocket?(env)

          socket = faye.new(env)
          wire_socket(socket)
          socket.rack_response
        end

        private

        def load_faye_websocket
          require "faye/websocket"
          Faye::WebSocket
        rescue LoadError
          nil
        end

        def wire_socket(socket)
          session_manager.on_output do |session_id, data|
            socket.send(ProtocolHandler.output(session_id, data))
          end
          session_manager.on_exit do |session_id, code|
            socket.send(ProtocolHandler.session_exit(session_id, code))
          end

          socket.on(:message) do |event|
            response = session_manager.process_message(ProtocolHandler.decode_frame(event.data))
            socket.send(response) if response
          rescue ProtocolError => e
            socket.send(ProtocolHandler.error(e.message))
          end
        end
      end
    end
  end
end
