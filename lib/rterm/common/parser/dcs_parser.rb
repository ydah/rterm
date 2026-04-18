# frozen_string_literal: true

module RTerm
  module Common
    # Utility parser for simple DCS payloads.
    module DcsParser
      Result = Struct.new(:params, :prefix, :intermediates, :final, :data, keyword_init: true)

      # @param payload [String]
      # @return [Result]
      def self.parse(payload)
        text = payload.to_s
        match = text.match(/\A([0-9;]*)([<=>?]?)([ -\/]*)([@-~])(.*)\z/m)
        return Result.new(params: [], prefix: "", intermediates: "", final: "", data: text) unless match

        Result.new(
          params: parse_params(match[1]),
          prefix: match[2],
          intermediates: match[3],
          final: match[4],
          data: match[5]
        )
      end

      def self.parse_params(params)
        return [] if params.empty?

        params.split(";").map { |param| param.empty? ? 0 : param.to_i }
      end
      private_class_method :parse_params
    end
  end
end
