# frozen_string_literal: true

module RTerm
  module Common
    # A fixed-capacity ring buffer (circular list) that automatically discards
    # the oldest elements when the maximum length is exceeded.
    # Used as the underlying storage for terminal scrollback buffers.
    class CircularList
      include Enumerable

      # @return [Integer] the current number of elements
      attr_reader :length

      # @param max_length [Integer] the maximum number of elements
      def initialize(max_length)
        @max_length = max_length
        @array = Array.new(max_length)
        @start = 0
        @length = 0
      end

      # @return [Integer] the maximum number of elements
      def max_length
        @max_length
      end

      # Sets a new maximum length, truncating elements if necessary.
      # @param value [Integer] the new maximum length
      def max_length=(value)
        if value < @length
          # Keep the most recent elements
          new_array = Array.new(value)
          value.times do |i|
            new_array[i] = @array[(@start + @length - value + i) % @max_length]
          end
          @array = new_array
          @start = 0
          @length = value
        else
          new_array = Array.new(value)
          @length.times do |i|
            new_array[i] = @array[(@start + i) % @max_length]
          end
          @array = new_array
          @start = 0
        end
        @max_length = value
      end

      # Returns the element at the given index.
      # @param index [Integer] the index (0-based from the logical start)
      # @return [Object, nil]
      def [](index)
        return nil if index < 0 || index >= @length

        @array[(@start + index) % @max_length]
      end

      # Sets the element at the given index.
      # @param index [Integer] the index (0-based from the logical start)
      # @param value [Object] the value to set
      def []=(index, value)
        return if index < 0 || index >= @length

        @array[(@start + index) % @max_length] = value
      end

      # Appends a value to the end. If the list is full, the oldest element is discarded.
      # @param value [Object] the value to append
      # @return [void]
      def push(value)
        @array[(@start + @length) % @max_length] = value
        if @length == @max_length
          @start = (@start + 1) % @max_length
        else
          @length += 1
        end
      end

      # Removes and returns the last element.
      # @return [Object, nil]
      def pop
        return nil if @length == 0

        @length -= 1
        index = (@start + @length) % @max_length
        value = @array[index]
        @array[index] = nil
        value
      end

      # Removes elements and/or inserts new elements at the given position.
      # @param start [Integer] the start index
      # @param delete_count [Integer] the number of elements to remove
      # @param items [Array] elements to insert
      # @return [void]
      def splice(start, delete_count, *items)
        start = [[start, 0].max, @length].min

        delete_count = [delete_count, @length - start].min

        # Collect elements after the deleted range
        after = []
        (start + delete_count...@length).each do |i|
          after << self[i]
        end

        # Set new length to start position
        @length = start

        # Push new items
        items.each { |item| push(item) }

        # Push back the elements that were after the deleted range
        after.each { |item| push(item) }
      end

      # Removes count elements from the beginning.
      # @param count [Integer] the number of elements to remove
      # @return [void]
      def trim_start(count)
        return if count <= 0

        count = [count, @length].min
        @start = (@start + count) % @max_length
        @length -= count
      end

      # Shifts elements within the list.
      # @param start [Integer] the start index of the range to shift
      # @param count [Integer] the number of elements to shift
      # @param offset [Integer] the offset to shift by (positive = right, negative = left)
      # @return [void]
      def shift_elements(start, count, offset)
        return if count <= 0 || offset == 0
        return if start < 0 || start >= @length

        count = [count, @length - start].min

        if offset > 0
          # Shift right — iterate from end to avoid overwriting
          (count - 1).downto(0) do |i|
            src = start + i
            dst = src + offset
            next if dst >= @length

            self[dst] = self[src]
          end
        else
          # Shift left — iterate from start
          count.times do |i|
            src = start + i
            dst = src + offset
            next if dst < 0

            self[dst] = self[src]
          end
        end
      end

      # Yields each element in order.
      # @yield [Object] each element
      # @return [Enumerator] if no block given
      def each(&block)
        return to_enum(:each) unless block

        @length.times do |i|
          block.call(@array[(@start + i) % @max_length])
        end
      end

      # Removes all elements.
      # @return [void]
      def clear
        @array = Array.new(@max_length)
        @start = 0
        @length = 0
      end

      # @return [Boolean] whether the list is at maximum capacity
      def full?
        @length == @max_length
      end
    end
  end
end
