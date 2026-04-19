# frozen_string_literal: true

module RTerm
  module Services
    class LogService
      LEVELS = {
        trace: 0,
        debug: 1,
        info: 2,
        warn: 3,
        error: 4,
        off: 5
      }.freeze

      attr_reader :level, :entries

      def initialize(level: :info, sink: nil)
        @level = normalize_level(level)
        @sink = sink
        @entries = []
      end

      def enabled?(level)
        LEVELS.fetch(normalize_level(level)) >= LEVELS.fetch(@level) && @level != :off
      end

      def log(level, message = nil, **fields)
        level = normalize_level(level)
        return nil unless enabled?(level)

        entry = {
          level: level,
          message: message.to_s,
          fields: fields
        }
        @entries << entry
        @sink&.call(entry)
        entry
      end

      LEVELS.each_key do |name|
        define_method(name) { |message = nil, **fields| log(name, message, **fields) }
      end

      private

      def normalize_level(value)
        level = value.to_s.downcase.to_sym
        LEVELS.key?(level) ? level : :info
      end
    end
  end
end
