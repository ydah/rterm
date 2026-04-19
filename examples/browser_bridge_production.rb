# frozen_string_literal: true

require "securerandom"
require "rterm"

allowed_origins = ENV.fetch("RTERM_ALLOWED_ORIGINS", "https://example.com").split(",")
auth_token = ENV.fetch("RTERM_BRIDGE_TOKEN")

# Gemfile for Rack deployment:
# gem "rterm"
# gem "faye-websocket"

RTerm::BrowserBridge::WebSocketServer.configure_secure_defaults do |config|
  config.allowed_origins = allowed_origins
  config.session_timeout = 60 * 60
  config.idle_timeout = 10 * 60
  config.rate_limit = { interval: 1.0, limit: 200 }
  config.authenticator = lambda do |message|
    payload = message[:payload] || message["payload"] || {}
    token = payload[:token] || payload["token"]

    token == auth_token
  end
  config.terminal_options = config.terminal_options.merge(scrollback: 5_000)
end

# config.ru:
# require_relative "examples/browser_bridge_production"
# run ->(env) { RTerm::BrowserBridge::WebSocketServer.handle(env) }
puts "Configured BrowserBridge #{SecureRandom.hex(4)} for Rack WebSocket deployment."
