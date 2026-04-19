# frozen_string_literal: true

RSpec.describe RTerm::BrowserBridge::ProtocolHandler do
  describe '.encode' do
    it 'encodes a message to JSON' do
      json = described_class.encode('output', session_id: 'abc', payload: { 'data' => 'hello' })
      parsed = JSON.parse(json)
      expect(parsed['type']).to eq('output')
      expect(parsed['session_id']).to eq('abc')
      expect(parsed['payload']['data']).to eq('hello')
    end

    it 'omits session_id when nil' do
      json = described_class.encode('pong')
      parsed = JSON.parse(json)
      expect(parsed).not_to have_key('session_id')
    end
  end

  describe '.decode' do
    it 'decodes a valid JSON message' do
      json = '{"type":"input","session_id":"abc","payload":{"data":"hello"}}'
      result = described_class.decode(json)
      expect(result[:type]).to eq('input')
      expect(result[:session_id]).to eq('abc')
      expect(result[:payload]['data']).to eq('hello')
    end

    it 'raises ProtocolError on missing type' do
      expect { described_class.decode('{"payload":{}}') }
        .to raise_error(RTerm::BrowserBridge::ProtocolError, /Missing 'type'/)
    end

    it 'raises ProtocolError on invalid JSON' do
      expect { described_class.decode('not json') }
        .to raise_error(RTerm::BrowserBridge::ProtocolError, /Invalid JSON/)
    end

    it 'defaults payload to empty hash' do
      result = described_class.decode('{"type":"ping"}')
      expect(result[:payload]).to eq({})
    end
  end

  describe '.decode_frame' do
    it 'decodes JSON frames' do
      result = described_class.decode_frame('{"type":"ping"}')

      expect(result).to eq({ type: 'ping', session_id: nil, payload: {} })
    end

    it 'decodes binary frames' do
      frame = described_class.encode_binary(:input, "abc", session_id: "s1")

      result = described_class.decode_frame(frame)

      expect(result).to eq({ type: 'input', session_id: 's1', payload: { 'data' => 'abc' } })
    end
  end

  describe 'convenience methods' do
    it '.output creates output message' do
      json = described_class.output('s1', 'data')
      msg = JSON.parse(json)
      expect(msg['type']).to eq('output')
      expect(msg['payload']['data']).to eq('data')
    end

    it '.session_created creates session_created message' do
      json = described_class.session_created('s1')
      msg = JSON.parse(json)
      expect(msg['type']).to eq('session_created')
      expect(msg['session_id']).to eq('s1')
    end

    it '.session_resumed creates session_resumed message' do
      json = described_class.session_resumed('s1', 'client_id' => 'c1')
      msg = JSON.parse(json)
      expect(msg['type']).to eq('session_resumed')
      expect(msg['session_id']).to eq('s1')
      expect(msg['payload']['client_id']).to eq('c1')
    end

    it '.negotiated creates negotiated message' do
      json = described_class.negotiated(binary: true)
      msg = JSON.parse(json)
      expect(msg['type']).to eq('negotiated')
      expect(msg['payload']['binary']).to be true
    end

    it '.pong creates pong message' do
      json = described_class.pong
      msg = JSON.parse(json)
      expect(msg['type']).to eq('pong')
    end

    it '.error creates error message' do
      json = described_class.error('something went wrong', session_id: 's1', code: 'boom')
      msg = JSON.parse(json)
      expect(msg['type']).to eq('error')
      expect(msg['payload']['message']).to eq('something went wrong')
      expect(msg['payload']['code']).to eq('boom')
    end
  end

  describe 'binary frames' do
    it 'encodes and decodes input frames' do
      frame = described_class.encode_binary(:input, "abc")
      decoded = described_class.decode_binary(frame)

      expect(decoded).to eq({ type: 'input', payload: { 'data' => 'abc' } })
    end

    it 'encodes and decodes session-scoped input frames' do
      frame = described_class.encode_binary(:input, "abc", session_id: "session-1")
      decoded = described_class.decode_binary(frame)

      expect(decoded).to eq({ type: 'input', session_id: 'session-1', payload: { 'data' => 'abc' } })
    end

    it 'encodes and decodes output frames' do
      frame = described_class.encode_binary(:output, "xyz")
      decoded = described_class.decode_binary(frame)

      expect(decoded).to eq({ type: 'output', payload: { 'data' => 'xyz' } })
    end

    it 'detects binary frames' do
      expect(described_class.binary_frame?(described_class.encode_binary(:input, "abc"))).to be true
      expect(described_class.binary_frame?('{"type":"ping"}')).to be false
    end

    it 'rejects unknown binary frame flags' do
      expect { described_class.decode_binary("\xFFbad".b) }
        .to raise_error(RTerm::BrowserBridge::ProtocolError, /Unknown binary frame/)
    end

    it 'rejects truncated session-scoped binary frames' do
      expect { described_class.decode_binary([0x81, 0, 5].pack("C*") + "ab") }
        .to raise_error(RTerm::BrowserBridge::ProtocolError, /Truncated binary frame session_id/)
    end
  end
end

RSpec.describe RTerm::BrowserBridge::SessionManager do
  let(:manager) { described_class.new(max_sessions: 3) }

  describe '#create_session' do
    it 'creates a new session and returns an ID' do
      id = manager.create_session
      expect(id).to be_a(String)
      expect(manager.session_count).to eq(1)
    end

    it 'raises when max sessions reached' do
      3.times { manager.create_session }
      expect { manager.create_session }
        .to raise_error(RTerm::BrowserBridge::SessionError, /Maximum sessions/)
    end

    it 'cleans up sessions past absolute timeout' do
      now = Time.at(100)
      timed = described_class.new(max_sessions: 3, session_timeout: 10, clock: -> { now })
      id = timed.create_session

      now = Time.at(111)
      timed.cleanup_expired

      expect(timed.session_exists?(id)).to be false
    end

    it 'cleans up idle sessions' do
      now = Time.at(100)
      timed = described_class.new(max_sessions: 3, idle_timeout: 10, clock: -> { now })
      id = timed.create_session
      now = Time.at(105)
      timed.write(id, "touch")
      now = Time.at(114)
      timed.cleanup_expired
      expect(timed.session_exists?(id)).to be true

      now = Time.at(116)
      timed.cleanup_expired
      expect(timed.session_exists?(id)).to be false
    end
  end

  describe '#destroy_session' do
    it 'removes the session' do
      id = manager.create_session
      manager.destroy_session(id)
      expect(manager.session_count).to eq(0)
    end

    it 'raises for unknown session' do
      expect { manager.destroy_session('nonexistent') }
        .to raise_error(RTerm::BrowserBridge::SessionError, /not found/)
    end
  end

  describe '#get_terminal' do
    it 'returns the terminal for a session' do
      id = manager.create_session
      expect(manager.get_terminal(id)).to be_a(RTerm::Terminal)
    end
  end

  describe '#write' do
    it 'writes data to the session terminal' do
      id = manager.create_session
      manager.write(id, "Hello")
      terminal = manager.get_terminal(id)
      expect(terminal.buffer.active.get_line(0).to_string).to eq("Hello")
    end

    it 'forwards input to PTY-backed sessions and emits output' do
      skip "PTY not available" unless defined?(::PTY)

      pty_manager = described_class.new(max_sessions: 1)
      received = +""
      pty_manager.on_output { |_session_id, data| received << data }

      id = pty_manager.create_session(command: "/bin/cat")
      sleep 0.1
      pty_manager.write(id, "bridge\n")

      10.times do
        break if received.include?("bridge")

        sleep 0.1
      end
      pty_manager.destroy_session(id)

      expect(received).to include("bridge")
    end

    it 'removes PTY-backed sessions when the process exits' do
      skip "PTY not available" unless defined?(::PTY)

      pty_manager = described_class.new(max_sessions: 1)
      exited = nil
      pty_manager.on_exit { |session_id, code| exited = [session_id, code] }

      id = pty_manager.create_session(command: "/bin/echo", args: ["done"])
      pty_manager.on_output { |_session_id, _data| }

      10.times do
        break unless pty_manager.session_exists?(id)

        sleep 0.1
      end

      expect(pty_manager.session_exists?(id)).to be false
      expect(exited).to eq([id, 0])
    end
  end

  describe '#resize' do
    it 'resizes the session terminal' do
      id = manager.create_session(cols: 80, rows: 24)
      manager.resize(id, 120, 40)
      terminal = manager.get_terminal(id)
      expect(terminal.cols).to eq(120)
      expect(terminal.rows).to eq(40)
    end
  end

  describe '#attach_session and #resume_session' do
    it 'attaches clients and returns a session snapshot' do
      id = manager.create_session(cols: 100, rows: 30)

      snapshot = manager.attach_session(id, client_id: "client-1")

      expect(snapshot).to include("client_id" => "client-1", "cols" => 100, "rows" => 30)
      expect(manager.attached_clients(id)).to eq(["client-1"])
    end

    it 'supports single-client attach policy' do
      single = described_class.new(attach_policy: :single)
      id = single.create_session
      single.attach_session(id, client_id: "client-1")

      expect { single.attach_session(id, client_id: "client-2") }
        .to raise_error(RTerm::BrowserBridge::SessionError, /already has an attached client/)
    end

    it 'supports replace attach policy' do
      replacing = described_class.new(attach_policy: :replace)
      id = replacing.create_session
      replacing.attach_session(id, client_id: "client-1")
      replacing.attach_session(id, client_id: "client-2")

      expect(replacing.attached_clients(id)).to eq(["client-2"])
    end

    it 'resumes an existing session by attaching and returning current state' do
      id = manager.create_session
      manager.write(id, "Hello")

      snapshot = manager.resume_session(id, client_id: "client-1")

      expect(snapshot["client_id"]).to eq("client-1")
      expect(snapshot["modes"]).to include(:wraparound_mode)
      expect(manager.attached_clients(id)).to eq(["client-1"])
    end
  end

  describe '#process_message' do
    it 'handles create_session' do
      msg = { type: 'create_session', session_id: nil, payload: { 'cols' => 80, 'rows' => 24 } }
      response = manager.process_message(msg)
      parsed = JSON.parse(response)
      expect(parsed['type']).to eq('session_created')
      expect(manager.session_count).to eq(1)
    end

    it 'handles ping' do
      msg = { type: 'ping', session_id: nil, payload: {} }
      response = manager.process_message(msg)
      parsed = JSON.parse(response)
      expect(parsed['type']).to eq('pong')
    end

    it 'handles input' do
      id = manager.create_session
      msg = { type: 'input', session_id: id, payload: { 'data' => 'Hello' } }
      manager.process_message(msg)
      expect(manager.get_terminal(id).buffer.active.get_line(0).to_string).to eq("Hello")
    end

    it 'handles resize' do
      id = manager.create_session
      msg = { type: 'resize', session_id: id, payload: { 'cols' => 120, 'rows' => 40 } }
      manager.process_message(msg)
      expect(manager.get_terminal(id).cols).to eq(120)
    end

    it 'handles destroy_session' do
      id = manager.create_session
      msg = { type: 'destroy_session', session_id: id, payload: {} }
      response = manager.process_message(msg)
      parsed = JSON.parse(response)
      expect(parsed['type']).to eq('session_destroyed')
      expect(manager.session_count).to eq(0)
    end

    it 'handles resume_session' do
      id = manager.create_session(cols: 90, rows: 25)
      msg = { type: 'resume_session', session_id: id, payload: { 'client_id' => 'client-1' } }

      response = manager.process_message(msg)
      parsed = JSON.parse(response)

      expect(parsed['type']).to eq('session_resumed')
      expect(parsed['session_id']).to eq(id)
      expect(parsed['payload']['client_id']).to eq('client-1')
      expect(parsed['payload']['cols']).to eq(90)
    end

    it 'handles detach_session' do
      id = manager.create_session
      manager.attach_session(id, client_id: "client-1")

      response = manager.process_message(type: 'detach_session', session_id: id, payload: { 'client_id' => 'client-1' })
      parsed = JSON.parse(response)

      expect(parsed['type']).to eq('session_detached')
      expect(manager.attached_clients(id)).to eq([])
    end

    it 'returns error for unknown message type' do
      msg = { type: 'unknown', session_id: nil, payload: {} }
      response = manager.process_message(msg)
      parsed = JSON.parse(response)
      expect(parsed['type']).to eq('error')
    end

    it 'returns error for invalid session' do
      msg = { type: 'input', session_id: 'bad', payload: { 'data' => 'x' } }
      response = manager.process_message(msg)
      parsed = JSON.parse(response)
      expect(parsed['type']).to eq('error')
    end

    it 'uses auth hooks to reject messages' do
      secure = described_class.new(authenticator: ->(_message) { false })
      msg = { type: 'ping', session_id: nil, payload: {} }

      response = secure.process_message(msg)
      parsed = JSON.parse(response)

      expect(parsed['type']).to eq('error')
      expect(parsed['payload']['message']).to include('Unauthorized')
      expect(parsed['payload']['code']).to eq('unauthorized')
    end

    it 'rejects oversized messages' do
      limited = described_class.new(max_message_bytes: 20)
      msg = { type: 'input', session_id: 'abc', payload: { 'data' => 'x' * 50 } }

      response = limited.process_message(msg)
      parsed = JSON.parse(response)

      expect(parsed['payload']['code']).to eq('message_too_large')
    end

    it 'rate limits messages' do
      now = Time.at(100)
      limited = described_class.new(rate_limit: { limit: 1, interval: 10 }, clock: -> { now })
      msg = { type: 'ping', session_id: nil, payload: {} }

      expect(JSON.parse(limited.process_message(msg))['type']).to eq('pong')
      response = limited.process_message(msg)

      expect(JSON.parse(response)['payload']['code']).to eq('rate_limited')
    end

    it 'expires sessions that miss heartbeats' do
      now = Time.at(100)
      timed = described_class.new(heartbeat_timeout: 10, clock: -> { now })
      id = timed.create_session

      now = Time.at(105)
      timed.process_message(type: 'ping', session_id: id, payload: {})
      now = Time.at(112)
      timed.cleanup_expired
      expect(timed.session_exists?(id)).to be true

      now = Time.at(116)
      timed.cleanup_expired
      expect(timed.session_exists?(id)).to be false
    end
  end

  describe 'output backpressure' do
    it 'queues and flushes output when auto flushing is disabled' do
      queued = described_class.new(auto_flush_output: false)
      id = queued.create_session
      received = +""
      queued.on_output { |_session_id, data| received << data }

      queued.queue_output(id, "abc")
      expect(received).to eq("")
      expect(queued.pending_output_bytes(id)).to eq(3)

      queued.flush_output(id)
      expect(received).to eq("abc")
      expect(queued.pending_output_bytes(id)).to eq(0)
    end

    it 'destroys sessions that exceed output queue limits' do
      queued = described_class.new(auto_flush_output: false, output_queue_limit: 2)
      id = queued.create_session

      queued.queue_output(id, "abc")

      expect(queued.session_exists?(id)).to be false
    end
  end

  describe '#session_exists?' do
    it 'returns true for existing session' do
      id = manager.create_session
      expect(manager.session_exists?(id)).to be true
    end

    it 'returns false for nonexistent session' do
      expect(manager.session_exists?('nope')).to be false
    end
  end

  describe '#session_ids' do
    it 'returns all session IDs' do
      id1 = manager.create_session
      id2 = manager.create_session
      expect(manager.session_ids).to contain_exactly(id1, id2)
    end
  end
end
