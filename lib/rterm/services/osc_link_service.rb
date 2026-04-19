# frozen_string_literal: true

module RTerm
  module Services
    class OscLinkService
      def initialize
        @active_link = nil
        @history = []
      end

      attr_reader :history

      def update(payload)
        params = (payload[:params] || payload["params"] || "").to_s
        uri = (payload[:uri] || payload["uri"] || "").to_s
        @active_link = uri.empty? ? nil : { params: params, uri: uri }
        @history << { params: params, uri: uri }
        active_link
      end

      def active_link
        @active_link&.dup
      end
    end
  end
end
