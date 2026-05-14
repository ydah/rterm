# frozen_string_literal: true

require_relative "../renderer_lifecycle"

module RTerm
  module Addon
    class WebGL < RendererLifecycle
      DEFAULT_CAPABILITIES = {
        accelerated: true,
        context_type: "webgl2",
        texture_atlas: true
      }.freeze
      RENDERER_TYPE = :webgl

      def state
        super.merge(texture_atlas_clears: render_cache_clears)
      end

      def clear_texture_atlas
        clear_render_cache
      end

      def texture_atlas_clears
        render_cache_clears
      end

      def on_texture_atlas_clear(&block)
        on_render_cache_clear(&block)
      end

      alias clearTextureAtlas clear_texture_atlas
      alias textureAtlasClears texture_atlas_clears
      alias onContextLoss on_context_loss
      alias onContextRestore on_context_restore
      alias onTextureAtlasClear on_texture_atlas_clear

      private

      def cache_event_name
        :texture_atlas_clear
      end
    end
  end
end
