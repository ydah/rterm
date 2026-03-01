# frozen_string_literal: true

# Example: WebSocket terminal server using the BrowserBridge protocol
#
# This example shows how to use the SessionManager and ProtocolHandler
# to manage terminal sessions over WebSocket.
#
# For a real implementation, you would use a WebSocket library like
# faye-websocket or websocket-driver.

require_relative "../lib/rterm"

# Create a session manager
manager = RTerm::BrowserBridge::SessionManager.new(max_sessions: 10)

# Simulate handling WebSocket messages
def handle_message(manager, raw_json)
  message = RTerm::BrowserBridge::ProtocolHandler.decode(raw_json)
  response = manager.process_message(message)
  puts "Response: #{response}" if response
  response
rescue RTerm::BrowserBridge::ProtocolError => e
  puts "Protocol error: #{e.message}"
end

# Simulate a client session
puts "=== Creating session ==="
response = handle_message(manager, '{"type":"create_session","payload":{"cols":80,"rows":24}}')
session = JSON.parse(response)
session_id = session["session_id"]
puts "Session ID: #{session_id}"

puts "\n=== Sending input ==="
handle_message(manager, %({"type":"input","session_id":"#{session_id}","payload":{"data":"Hello World"}}))

# Check the terminal buffer
terminal = manager.get_terminal(session_id)
puts "Buffer content: #{terminal.buffer.active.get_line(0).to_string}"

puts "\n=== Resizing ==="
handle_message(manager, %({"type":"resize","session_id":"#{session_id}","payload":{"cols":120,"rows":40}}))
puts "New size: #{terminal.cols}x#{terminal.rows}"

puts "\n=== Ping ==="
handle_message(manager, '{"type":"ping"}')

puts "\n=== Destroying session ==="
handle_message(manager, %({"type":"destroy_session","session_id":"#{session_id}"}))
puts "Sessions remaining: #{manager.session_count}"
