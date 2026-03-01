# frozen_string_literal: true

RSpec.describe RTerm::Common::EventEmitter do
  let(:emitter_class) do
    Class.new do
      include RTerm::Common::EventEmitter
    end
  end

  let(:emitter) { emitter_class.new }

  describe "#on and #emit" do
    it "calls the registered listener when the event is emitted" do
      called = false
      emitter.on(:test) { called = true }
      emitter.emit(:test)
      expect(called).to be true
    end

    it "passes arguments to the listener" do
      received = nil
      emitter.on(:data) { |arg| received = arg }
      emitter.emit(:data, "hello")
      expect(received).to eq("hello")
    end

    it "passes multiple arguments to the listener" do
      received = nil
      emitter.on(:multi) { |a, b| received = [a, b] }
      emitter.emit(:multi, 1, 2)
      expect(received).to eq([1, 2])
    end

    it "supports multiple listeners on the same event" do
      calls = []
      emitter.on(:test) { calls << :first }
      emitter.on(:test) { calls << :second }
      emitter.emit(:test)
      expect(calls).to eq(%i[first second])
    end

    it "returns a Disposable" do
      disposable = emitter.on(:test) { nil }
      expect(disposable).to be_a(RTerm::Common::Disposable)
    end
  end

  describe "#once" do
    it "calls the listener only once" do
      call_count = 0
      emitter.once(:test) { call_count += 1 }
      emitter.emit(:test)
      emitter.emit(:test)
      expect(call_count).to eq(1)
    end

    it "passes arguments to the one-time listener" do
      received = nil
      emitter.once(:data) { |arg| received = arg }
      emitter.emit(:data, "value")
      expect(received).to eq("value")
    end

    it "returns a Disposable" do
      disposable = emitter.once(:test) { nil }
      expect(disposable).to be_a(RTerm::Common::Disposable)
    end
  end

  describe "#off" do
    it "removes a specific listener" do
      call_count = 0
      listener = proc { call_count += 1 }
      emitter.on(:test, &listener)
      emitter.off(:test, listener)
      emitter.emit(:test)
      expect(call_count).to eq(0)
    end
  end

  describe "Disposable#dispose" do
    it "unsubscribes the listener when disposed" do
      call_count = 0
      disposable = emitter.on(:test) { call_count += 1 }
      disposable.dispose
      emitter.emit(:test)
      expect(call_count).to eq(0)
    end

    it "is idempotent" do
      disposable = emitter.on(:test) { nil }
      disposable.dispose
      expect { disposable.dispose }.not_to raise_error
    end

    it "reports disposed? correctly" do
      disposable = emitter.on(:test) { nil }
      expect(disposable.disposed?).to be false
      disposable.dispose
      expect(disposable.disposed?).to be true
    end
  end

  describe "#remove_all_listeners" do
    it "removes all listeners for a specific event" do
      calls = []
      emitter.on(:a) { calls << :a }
      emitter.on(:b) { calls << :b }
      emitter.remove_all_listeners(:a)
      emitter.emit(:a)
      emitter.emit(:b)
      expect(calls).to eq([:b])
    end

    it "removes all listeners when no event is specified" do
      calls = []
      emitter.on(:a) { calls << :a }
      emitter.on(:b) { calls << :b }
      emitter.remove_all_listeners
      emitter.emit(:a)
      emitter.emit(:b)
      expect(calls).to be_empty
    end
  end

  describe "#listener_count" do
    it "returns the number of listeners for an event" do
      emitter.on(:test) { nil }
      emitter.on(:test) { nil }
      expect(emitter.listener_count(:test)).to eq(2)
    end

    it "returns 0 for an event with no listeners" do
      expect(emitter.listener_count(:unknown)).to eq(0)
    end
  end

  describe "#emit with no listeners" do
    it "does not raise an error" do
      expect { emitter.emit(:nonexistent) }.not_to raise_error
    end
  end
end
