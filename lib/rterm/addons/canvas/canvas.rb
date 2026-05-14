# frozen_string_literal: true

require_relative "../renderer_lifecycle"

module RTerm
  module Addon
    class Canvas < RendererLifecycle
      DEFAULT_CAPABILITIES = {
        accelerated: false,
        context_type: "2d",
        texture_atlas: false,
        render_cache: true
      }.freeze
      RENDERER_TYPE = :canvas
    end
  end
end
