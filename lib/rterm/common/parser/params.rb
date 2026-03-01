# frozen_string_literal: true

module RTerm
  module Common
    # Accumulates CSI/DCS parameters and sub-parameters during parsing.
    # Supports the colon-separated sub-parameter syntax (e.g., 38:2:R:G:B).
    class Params
      MAX_VALUE     = 0x7FFFFFFF
      MAX_LENGTH    = 32
      MAX_SUB_PARAMS = 256

      attr_reader :length

      # @param max_length [Integer] maximum number of parameters
      # @param max_sub_params_length [Integer] maximum number of sub-parameters
      def initialize(max_length = MAX_LENGTH, max_sub_params_length = MAX_SUB_PARAMS)
        @max_length = max_length
        @max_sub_params_length = max_sub_params_length
        @params = Array.new(max_length, 0)
        @length = 0
        @sub_params = Array.new(max_sub_params_length, 0)
        @sub_params_length = 0
        @sub_params_idx = Array.new(max_length, 0)
        @reject_digits = false
        @reject_sub_digits = false
        @digit_is_sub = false
      end

      # Returns the parameter at the given index.
      # @param index [Integer]
      # @return [Integer]
      def [](index)
        return 0 if index >= @length

        @params[index]
      end

      # Resets all parameters.
      def reset
        @length = 0
        @sub_params_length = 0
        @reject_digits = false
        @reject_sub_digits = false
        @digit_is_sub = false
      end

      # Adds a new parameter with the given value.
      # @param value [Integer]
      def add_param(value)
        @digit_is_sub = false
        if @length >= @max_length
          @reject_digits = true
          return
        end
        @sub_params_idx[@length] = (@sub_params_length << 8) | @sub_params_length
        @params[@length] = [value.to_i, MAX_VALUE].min
        @length += 1
      end

      # Adds a sub-parameter to the current parameter.
      # @param value [Integer]
      def add_sub_param(value)
        @digit_is_sub = true
        return if @length == 0
        if @reject_digits || @sub_params_length >= @max_sub_params_length
          @reject_sub_digits = true
          return
        end
        @sub_params[@sub_params_length] = [value.to_i, MAX_VALUE].min
        @sub_params_length += 1
        @sub_params_idx[@length - 1] = (@sub_params_idx[@length - 1] & 0xFF00) |
                                        ((@sub_params_idx[@length - 1] & 0xFF) + 1)
      end

      # Adds a digit to the current parameter or sub-parameter.
      # @param value [Integer] digit (0-9)
      def add_digit(value)
        if @digit_is_sub
          return if @reject_digits || @reject_sub_digits || @sub_params_length == 0

          cur = @sub_params[@sub_params_length - 1]
          @sub_params[@sub_params_length - 1] = if cur == -1
                                                   value
                                                 else
                                                   [cur * 10 + value, MAX_VALUE].min
                                                 end
        else
          return if @reject_digits || @length == 0

          cur = @params[@length - 1]
          @params[@length - 1] = if cur == -1
                                   value
                                 else
                                   [cur * 10 + value, MAX_VALUE].min
                                 end
        end
      end

      # Returns sub-parameters for the parameter at the given index.
      # @param index [Integer]
      # @return [Array<Integer>, nil]
      def get_sub_params(index)
        return nil if index >= @length

        start_pos = @sub_params_idx[index] >> 8
        end_pos = @sub_params_idx[index] & 0xFF
        return nil if end_pos - start_pos <= 0

        @sub_params[start_pos...end_pos]
      end

      # @param index [Integer]
      # @return [Boolean]
      def has_sub_params?(index)
        return false if index >= @length

        start_pos = @sub_params_idx[index] >> 8
        end_pos = @sub_params_idx[index] & 0xFF
        (end_pos - start_pos) > 0
      end

      # Converts parameters to an array representation.
      # @return [Array]
      def to_array
        result = []
        @length.times do |i|
          result << @params[i]
          sub = get_sub_params(i)
          result << sub if sub
        end
        result
      end
    end
  end
end
