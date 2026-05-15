# frozen_string_literal: true

module RTerm
  module BrowserAdapter
    ASSET_DIR = File.expand_path("browser_adapter", __dir__)

    module_function

    def javascript
      File.read(asset_path("browser_adapter.js"))
    end

    def stylesheet
      File.read(asset_path("browser_adapter.css"))
    end

    def asset_path(name)
      path = File.expand_path(name.to_s, ASSET_DIR)
      prefix = ASSET_DIR + File::SEPARATOR
      raise ArgumentError, "unknown browser adapter asset: #{name}" unless path.start_with?(prefix)
      raise Errno::ENOENT, path unless File.file?(path)

      path
    end

    def script_tag
      %(<script>#{javascript}</script>)
    end

    def style_tag
      %(<style>#{stylesheet}</style>)
    end
  end
end
