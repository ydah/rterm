# frozen_string_literal: true

require_relative "../base"

module RTerm
  module Addon
    class Fit < Base
      # Calculate terminal dimensions from pixel sizes
      # @param pixel_width [Integer] container width in pixels
      # @param pixel_height [Integer] container height in pixels
      # @param cell_width [Float] character cell width in pixels (default: 9.0)
      # @param cell_height [Float] character cell height in pixels (default: 17.0)
      # @return [Hash] {cols:, rows:}
      def propose_dimensions(pixel_width, pixel_height, cell_width: 9.0, cell_height: 17.0)
        cols = [(pixel_width / cell_width).floor, 1].max
        rows = [(pixel_height / cell_height).floor, 1].max
        { cols: cols, rows: rows }
      end

      # Calculate and apply resize
      # @param pixel_width [Integer] container width in pixels
      # @param pixel_height [Integer] container height in pixels
      # @return [Hash] {cols:, rows:}
      def fit(pixel_width, pixel_height, **opts)
        dims = propose_dimensions(pixel_width, pixel_height, **opts)
        @terminal.resize(dims[:cols], dims[:rows])
        dims
      end
    end
  end
end
