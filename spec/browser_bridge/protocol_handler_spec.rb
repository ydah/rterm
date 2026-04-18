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

    it '.pong creates pong message' do
      json = described_class.pong
      msg = JSON.parse(json)
      expect(msg['type']).to eq('pong')
    end

    it '.error creates error message' do
      json = described_class.error('something went wrong', session_id: 's1')
      msg = JSON.parse(json)
      expect(msg['type']).to eq('error')
      expect(msg['payload']['message']).to eq('something went wrong')
    end
  end

  describe 'binary frames' do
    it 'encodes and decodes input frames' do
      frame = described_class.encode_binary(:input, "abc")
      decoded = described_class.decode_binary(frame)

      expect(decoded).to eq({ type: 'input', payload: { 'data' => 'abc' } })
    end

    it 'encodes and decodes output frames' do
      frame = described_class.encode_binary(:output, "xyz")
      decoded = described_class.decode_binary(frame)

      expect(decoded).to eq({ type: 'output', payload: { 'data' => 'xyz' } })
    end

    it 'rejects unknown binary frame flags' do
      expect { described_class.decode_binary("\xFFbad".b) }
        .to raise_error(RTerm::BrowserBridge::ProtocolError, /Unknown binary frame/)
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
