# frozen_string_literal: true

module RTerm
  module Common
    # Disposable object returned by event listener registration.
    # Call #dispose to unsubscribe the listener.
    class Disposable
      def initialize(&dispose_block)
        @dispose_block = dispose_block
        @disposed = false
      end

      # Unsubscribes the listener. No-op if already disposed.
      # @return [void]
      def dispose
        return if @disposed

        @disposed = true
        @dispose_block&.call
        @dispose_block = nil
      end

      # @return [Boolean] whether this disposable has been disposed
      def disposed?
        @disposed
      end
    end

    # Event subscription and emission system.
    # Include this module to add event capabilities to any class.
    module EventEmitter
      # Registers a listener for the given event.
      # @param event [Symbol] the event name
      # @yield the block to call when the event is emitted
      # @return [Disposable] a disposable to unsubscribe the listener
      def on(event, &block)
        listeners_for(event) << block
        Disposable.new { listeners_for(event).delete(block) }
      end

      # Registers a one-time listener for the given event.
      # The listener is automatically removed after the first invocation.
      # @param event [Symbol] the event name
      # @yield the block to call once when the event is emitted
      # @return [Disposable] a disposable to unsubscribe the listener
      def once(event, &block)
        wrapper = proc do |*args|
          listeners_for(event).delete(wrapper)
          block.call(*args)
        end
        listeners_for(event) << wrapper
        Disposable.new { listeners_for(event).delete(wrapper) }
      end

      # Emits an event, calling all registered listeners with the given arguments.
      # @param event [Symbol] the event name
      # @param args [Array] arguments to pass to listeners
      # @return [void]
      def emit(event, *args)
        return unless @listeners&.key?(event)

        listeners_for(event).dup.each { |listener| listener.call(*args) }
      end

      # Removes a specific listener from an event.
      # @param event [Symbol] the event name
      # @param listener [Proc] the listener to remove
      # @return [void]
      def off(event, listener)
        listeners_for(event).delete(listener)
      end

      # Removes all listeners for a given event, or all listeners if no event is specified.
      # @param event [Symbol, nil] the event name, or nil to remove all
      # @return [void]
      def remove_all_listeners(event = nil)
        if event
          @listeners&.delete(event)
        else
          @listeners&.clear
        end
      end

      # Returns the number of listeners registered for the given event.
      # @param event [Symbol] the event name
      # @return [Integer]
      def listener_count(event)
        return 0 unless @listeners&.key?(event)

        listeners_for(event).size
      end

      private

      def listeners_for(event)
        @listeners ||= {}
        @listeners[event] ||= []
      end
    end
  end
end
