# frozen_string_literal: true

require 'json'

module RTerm
  module BrowserBridge
    # Handles encoding/decoding of JSON messages between
    # the Ruby backend and xterm.js frontend.
    class ProtocolHandler
      # Message types
      module MessageType
        # Client → Server
        INPUT           = 'input'
        RESIZE          = 'resize'
        CREATE_SESSION  = 'create_session'
        DESTROY_SESSION = 'destroy_session'
        PING            = 'ping'

        # Server → Client
        OUTPUT           = 'output'
        SESSION_CREATED  = 'session_created'
        SESSION_DESTROYED = 'session_destroyed'
        SESSION_EXIT     = 'session_exit'
        PONG             = 'pong'
        ERROR            = 'error'
      end

      module BinaryFrame
        INPUT = 0x01
        OUTPUT = 0x02
      end

      # Encode a message to JSON string
      # @param type [String] message type
      # @param session_id [String] session identifier
      # @param payload [Hash] message payload
      # @return [String] JSON encoded message
      def self.encode(type, session_id: nil, payload: {})
        msg = { 'type' => type }
        msg['session_id'] = session_id if session_id
        msg['payload'] = payload
        JSON.generate(msg)
      end

      # Decode a JSON message string
      # @param data [String] JSON encoded message
      # @return [Hash] parsed message with :type, :session_id, :payload
      # @raise [ProtocolError] if message is invalid
      def self.decode(data)
        parsed = JSON.parse(data)
        raise ProtocolError, "Missing 'type' field" unless parsed['type']

        {
          type: parsed['type'],
          session_id: parsed['session_id'],
          payload: parsed['payload'] || {}
        }
      rescue JSON::ParserError => e
        raise ProtocolError, "Invalid JSON: #{e.message}"
      end

      # Encode input/output data as a binary frame with a 1-byte type flag.
      # @param type [Symbol, String] :input or :output
      # @param data [String]
      # @return [String]
      def self.encode_binary(type, data)
        flag = case type.to_s
               when MessageType::INPUT then BinaryFrame::INPUT
               when MessageType::OUTPUT then BinaryFrame::OUTPUT
               else
                 raise ProtocolError, "Unsupported binary frame type: #{type}"
               end
        [flag].pack("C") + data.to_s.b
      end

      # Decode a binary input/output frame.
      # @param data [String]
      # @return [Hash]
      def self.decode_binary(data)
        bytes = data.to_s.b
        flag = bytes.getbyte(0)
        payload = bytes.byteslice(1..)&.force_encoding("UTF-8")&.scrub || ""

        case flag
        when BinaryFrame::INPUT
          { type: MessageType::INPUT, payload: { 'data' => payload } }
        when BinaryFrame::OUTPUT
          { type: MessageType::OUTPUT, payload: { 'data' => payload } }
        else
          raise ProtocolError, "Unknown binary frame flag: #{flag.inspect}"
        end
      end

      # Convenience methods for creating server messages
      def self.output(session_id, data)
        encode(MessageType::OUTPUT, session_id: session_id, payload: { 'data' => data })
      end

      def self.session_created(session_id)
        encode(MessageType::SESSION_CREATED, session_id: session_id)
      end

      def self.session_destroyed(session_id)
        encode(MessageType::SESSION_DESTROYED, session_id: session_id)
      end

      def self.session_exit(session_id, code)
        encode(MessageType::SESSION_EXIT, session_id: session_id, payload: { 'code' => code })
      end

      def self.pong
        encode(MessageType::PONG)
      end

      def self.error(message, session_id: nil)
        encode(MessageType::ERROR, session_id: session_id, payload: { 'message' => message })
      end
    end

    class ProtocolError < StandardError; end
  end
end
