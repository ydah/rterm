# frozen_string_literal: true

require "securerandom"
require "rterm"

allowed_origins = ENV.fetch("RTERM_ALLOWED_ORIGINS", "https://example.com").split(",")
auth_token = ENV.fetch("RTERM_BRIDGE_TOKEN")

RTerm::BrowserBridge::WebSocketServer.configure do |config|
  config.allowed_origins = allowed_origins
  config.max_message_bytes = 64 * 1024
  config.heartbeat_timeout = 30
  config.rate_limit = { interval: 1.0, max_messages: 200 }
  config.attach_policy = :single
  config.session_timeout = 60 * 60
  config.idle_timeout = 10 * 60
  config.authenticator = lambda do |message|
    message.dig(:payload, :token) == auth_token || message.dig("payload", "token") == auth_token
  end
  config.terminal_options = { scrollback: 5_000 }
end

# config.ru:
# require_relative "examples/browser_bridge_production"
# run ->(env) { RTerm::BrowserBridge::WebSocketServer.handle(env) }
puts "Configured BrowserBridge #{SecureRandom.hex(4)} for Rack WebSocket deployment."
