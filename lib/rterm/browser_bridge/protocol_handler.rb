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
        SESSION_ID = 0x80
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

      # Decode either a JSON message frame or a binary frame.
      # @param data [String]
      # @return [Hash]
      def self.decode_frame(data)
        bytes = data.to_s.b
        first = bytes.lstrip.getbyte(0)
        return decode(data) if first == "{".ord

        decode_binary(bytes)
      end

      # Encode input/output data as a binary frame with a 1-byte type flag.
      # @param type [Symbol, String] :input or :output
      # @param data [String]
      # @param session_id [String, nil]
      # @return [String]
      def self.encode_binary(type, data, session_id: nil)
        flag = case type.to_s
               when MessageType::INPUT then BinaryFrame::INPUT
               when MessageType::OUTPUT then BinaryFrame::OUTPUT
               else
                 raise ProtocolError, "Unsupported binary frame type: #{type}"
               end
        payload = data.to_s.b
        return [flag].pack("C") + payload unless session_id

        encoded_session_id = session_id.to_s.b
        if encoded_session_id.bytesize > 65_535
          raise ProtocolError, "Binary frame session_id is too long"
        end

        [flag | BinaryFrame::SESSION_ID, encoded_session_id.bytesize].pack("Cn") +
          encoded_session_id + payload
      end

      # Decode a binary input/output frame.
      # @param data [String]
      # @return [Hash]
      def self.decode_binary(data)
        bytes = data.to_s.b
        flag = bytes.getbyte(0)
        raise ProtocolError, "Empty binary frame" unless flag

        session_id = nil
        offset = 1
        if (flag & BinaryFrame::SESSION_ID) != 0
          flag &= ~BinaryFrame::SESSION_ID
          validate_binary_flag(flag)
          session_id, offset = decode_binary_session_id(bytes)
        end

        payload = bytes.byteslice(offset..)&.force_encoding("UTF-8")&.scrub || ""

        message = binary_message(flag, payload)
        message[:session_id] = session_id if session_id
        message
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

      def self.error(message, session_id: nil, code: nil)
        payload = { 'message' => message }
        payload['code'] = code if code
        encode(MessageType::ERROR, session_id: session_id, payload: payload)
      end

      def self.decode_binary_session_id(bytes)
        raise ProtocolError, "Truncated binary frame session_id length" if bytes.bytesize < 3

        length = bytes.byteslice(1, 2).unpack1("n")
        start = 3
        finish = start + length
        raise ProtocolError, "Truncated binary frame session_id" if bytes.bytesize < finish

        [bytes.byteslice(start, length).force_encoding("UTF-8").scrub, finish]
      end
      private_class_method :decode_binary_session_id

      def self.binary_message(flag, payload)
        validate_binary_flag(flag)
        case flag
        when BinaryFrame::INPUT
          { type: MessageType::INPUT, payload: { 'data' => payload } }
        when BinaryFrame::OUTPUT
          { type: MessageType::OUTPUT, payload: { 'data' => payload } }
        else
          raise ProtocolError, "Unknown binary frame flag: #{flag.inspect}"
        end
      end
      private_class_method :binary_message

      def self.validate_binary_flag(flag)
        return if [BinaryFrame::INPUT, BinaryFrame::OUTPUT].include?(flag)

        raise ProtocolError, "Unknown binary frame flag: #{flag.inspect}"
      end
      private_class_method :validate_binary_flag
    end

    class ProtocolError < StandardError; end
  end
end
