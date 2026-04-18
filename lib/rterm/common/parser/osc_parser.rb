# frozen_string_literal: true

module RTerm
  module Common
    # Utility parser for OSC payloads.
    module OscParser
      Result = Struct.new(:id, :data, keyword_init: true)

      # @param payload [String]
      # @return [Result]
      def self.parse(payload)
        id, data = payload.to_s.split(";", 2)
        Result.new(id: id.to_i, data: data || "")
      end
    end
  end
end
