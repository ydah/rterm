# frozen_string_literal: true

require_relative "../base"
require_relative "../../common/event_emitter"

module RTerm
  module Addon
    class Attach < Base
      include Common::EventEmitter

      def initialize(socket, bidirectional: true, input_utf8: true)
        @socket = socket
        @bidirectional = bidirectional
        @input_utf8 = input_utf8
        @disposables = []
      end

      attr_reader :socket

      def activate(terminal)
        super
        subscribe_terminal_input if @bidirectional
        subscribe_socket(:message) { |event| receive_data(event) }
        subscribe_socket(:open) { |event| emit(:open, event) }
        subscribe_socket(:close) { |event| emit(:close, event) }
        subscribe_socket(:error) { |event| emit(:error, event) }
      end

      def send_data(data)
        write_socket(outgoing_data(data))
      end

      def receive_data(event)
        ensure_active!
        data = incoming_data(event)
        return nil if data.nil?

        payload = normalize_data(data)
        @terminal.write(payload)
        emit(:message, payload)
        payload
      end

      def dispose
        @disposables.each(&:dispose)
        @disposables.clear
        super
      end

      alias sendData send_data
      alias receiveData receive_data

      private

      def ensure_active!
        raise RuntimeError, "Attach addon is not active" unless @terminal
      end

      def subscribe_terminal_input
        @disposables << @terminal.on(:data) { |data| send_data(data) }
        @disposables << @terminal.on(:binary) { |data| send_data(data) }
      end

      def subscribe_socket(event, &block)
        return unless @socket.respond_to?(:on)

        disposable = @socket.on(event, &block)
        if disposable.respond_to?(:dispose)
          @disposables << disposable
        elsif @socket.respond_to?(:off)
          @disposables << Common::Disposable.new { @socket.off(event, block) }
        end
      end

      def write_socket(data)
        if socket_send_method?
          @socket.send(data)
        elsif @socket.respond_to?(:write)
          @socket.write(data)
        elsif @socket.respond_to?(:<<)
          @socket << data
        else
          raise ArgumentError, "Socket must respond to #send, #write, or #<<"
        end
      end

      def socket_send_method?
        return false unless @socket.respond_to?(:send)

        owner = @socket.method(:send).owner
        owner != Kernel && owner != BasicObject
      rescue NameError
        false
      end

      def outgoing_data(data)
        payload = normalize_data(data)
        @input_utf8 ? payload : payload.b
      end

      def incoming_data(event)
        return event.data if event.respond_to?(:data)

        if event.respond_to?(:[])
          value = indexed_value(event, :data)
          return value unless value.nil?

          value = indexed_value(event, "data")
          return value unless value.nil?
        end

        event
      end

      def indexed_value(object, key)
        object[key]
      rescue StandardError
        nil
      end

      def normalize_data(data)
        return data if data.is_a?(String)
        return data.pack("C*") if data.is_a?(Array)

        data.to_s
      end
    end
  end
end
