# frozen_string_literal: true

RSpec.describe RTerm::Common::EscapeSequenceParser do
  let(:parser) { described_class.new }

  describe "printable characters" do
    it "dispatches printable ASCII to the print handler" do
      received = nil
      parser.set_print_handler { |data| received = data }
      parser.parse("Hello")
      expect(received).to eq("Hello")
    end

    it "dispatches non-ASCII printable characters" do
      received = nil
      parser.set_print_handler { |data| received = data }
      parser.parse("漢字")
      expect(received).to eq("漢字")
    end
  end

  describe "C0 control characters" do
    it "dispatches BEL (0x07)" do
      called = false
      parser.set_execute_handler(0x07) { called = true }
      parser.parse("\x07")
      expect(called).to be true
    end

    it "dispatches BS (0x08)" do
      called = false
      parser.set_execute_handler(0x08) { called = true }
      parser.parse("\x08")
      expect(called).to be true
    end

    it "dispatches HT (0x09)" do
      called = false
      parser.set_execute_handler(0x09) { called = true }
      parser.parse("\t")
      expect(called).to be true
    end

    it "dispatches LF (0x0A)" do
      called = false
      parser.set_execute_handler(0x0A) { called = true }
      parser.parse("\n")
      expect(called).to be true
    end

    it "dispatches CR (0x0D)" do
      called = false
      parser.set_execute_handler(0x0D) { called = true }
      parser.parse("\r")
      expect(called).to be true
    end
  end

  describe "CSI sequences" do
    it "parses CSI with single parameter" do
      received_params = nil
      parser.set_csi_handler({ final: "A" }) do |params|
        received_params = params.to_array
        true
      end
      parser.parse("\e[5A")
      expect(received_params).to eq([5])
    end

    it "parses CSI with multiple parameters" do
      received_params = nil
      parser.set_csi_handler({ final: "H" }) do |params|
        received_params = params.to_array
        true
      end
      parser.parse("\e[10;20H")
      expect(received_params).to eq([10, 20])
    end

    it "parses CSI with default parameters" do
      received_params = nil
      parser.set_csi_handler({ final: "H" }) do |params|
        received_params = [params[0], params[1]]
        true
      end
      parser.parse("\e[H")
      expect(received_params).to eq([0, 0])
    end

    it "parses CSI with prefix (?)" do
      received_params = nil
      parser.set_csi_handler({ prefix: "?", final: "h" }) do |params|
        received_params = params.to_array
        true
      end
      parser.parse("\e[?25h")
      expect(received_params).to eq([25])
    end

    it "parses SGR (CSI m)" do
      received_params = nil
      parser.set_csi_handler({ final: "m" }) do |params|
        received_params = params.to_array
        true
      end
      parser.parse("\e[1;31m")
      expect(received_params).to eq([1, 31])
    end

    it "parses CSI with many parameters" do
      received_params = nil
      parser.set_csi_handler({ final: "m" }) do |params|
        received_params = params.to_array
        true
      end
      parser.parse("\e[38;2;255;128;0m")
      expect(received_params).to eq([38, 2, 255, 128, 0])
    end
  end

  describe "ESC sequences" do
    it "dispatches ESC 7 (DECSC)" do
      called = false
      parser.set_esc_handler({ final: "7" }) { called = true; true }
      parser.parse("\e7")
      expect(called).to be true
    end

    it "dispatches ESC 8 (DECRC)" do
      called = false
      parser.set_esc_handler({ final: "8" }) { called = true; true }
      parser.parse("\e8")
      expect(called).to be true
    end

    it "dispatches ESC with intermediates" do
      called = false
      parser.set_esc_handler({ intermediates: "(", final: "B" }) { called = true; true }
      parser.parse("\e(B")
      expect(called).to be true
    end
  end

  describe "OSC sequences" do
    it "parses OSC 0 (set title) with BEL terminator" do
      received = nil
      parser.set_osc_handler(0) { |data| received = data }
      parser.parse("\e]0;My Title\x07")
      expect(received).to eq("My Title")
    end

    it "parses OSC 0 with ST (ESC \\) terminator" do
      received = nil
      parser.set_osc_handler(0) { |data| received = data }
      parser.parse("\e]0;My Title\e\\")
      expect(received).to eq("My Title")
    end

    it "parses OSC 2 (set title)" do
      received = nil
      parser.set_osc_handler(2) { |data| received = data }
      parser.parse("\e]2;Window Title\x07")
      expect(received).to eq("Window Title")
    end
  end

  describe "invalid sequences" do
    it "returns to GROUND on invalid sequences" do
      printed = nil
      parser.set_print_handler { |data| printed = data }
      parser.parse("\e[!abc")  # invalid CSI, then print "bc"
      expect(parser.current_state).to eq(RTerm::Common::ParserState::GROUND)
    end

    it "does not raise on unknown sequences" do
      expect { parser.parse("\e[?9999z") }.not_to raise_error
    end
  end

  describe "UTF-8 transparency" do
    it "passes through multi-byte UTF-8 characters" do
      received = nil
      parser.set_print_handler { |data| received = data }
      parser.parse("日本語テスト")
      expect(received).to eq("日本語テスト")
    end
  end

  describe "mixed content" do
    it "handles text interleaved with control sequences" do
      prints = []
      csi_calls = []
      parser.set_print_handler { |data| prints << data }
      parser.set_csi_handler({ final: "m" }) do |params|
        csi_calls << params.to_array
        true
      end
      parser.parse("Hello \e[1;31mWorld\e[0m!")
      expect(prints).to eq(["Hello ", "World", "!"])
      expect(csi_calls).to eq([[1, 31], [0]])
    end
  end

  describe "#reset" do
    it "resets parser state to GROUND" do
      parser.parse("\e[")  # enter CSI_ENTRY
      parser.reset
      expect(parser.current_state).to eq(RTerm::Common::ParserState::GROUND)
    end
  end
end

RSpec.describe RTerm::Common::Params do
  describe "#add_param and #[]" do
    it "accumulates parameters" do
      params = described_class.new
      params.add_param(5)
      params.add_param(10)
      expect(params[0]).to eq(5)
      expect(params[1]).to eq(10)
      expect(params.length).to eq(2)
    end

    it "returns 0 for out-of-bounds index" do
      params = described_class.new
      expect(params[0]).to eq(0)
    end
  end

  describe "#add_digit" do
    it "builds multi-digit parameters" do
      params = described_class.new
      params.add_param(0)
      params.add_digit(1)
      params.add_digit(2)
      params.add_digit(3)
      expect(params[0]).to eq(123)
    end
  end

  describe "#add_sub_param" do
    it "adds sub-parameters" do
      params = described_class.new
      params.add_param(38)
      params.add_sub_param(-1)
      params.add_digit(2)
      params.add_sub_param(-1)
      params.add_digit(2)
      params.add_digit(5)
      params.add_digit(5)
      expect(params[0]).to eq(38)
      expect(params.get_sub_params(0)).to eq([2, 255])
    end

    it "reports has_sub_params? correctly" do
      params = described_class.new
      params.add_param(38)
      expect(params.has_sub_params?(0)).to be false
      params.add_sub_param(2)
      expect(params.has_sub_params?(0)).to be true
    end
  end

  describe "#reset" do
    it "clears all parameters" do
      params = described_class.new
      params.add_param(1)
      params.add_param(2)
      params.reset
      expect(params.length).to eq(0)
    end
  end

  describe "#to_array" do
    it "converts to array with sub-parameters" do
      params = described_class.new
      params.add_param(1)
      params.add_param(38)
      params.add_sub_param(2)
      params.add_sub_param(0)
      params.add_param(5)
      expect(params.to_array).to eq([1, 38, [2, 0], 5])
    end
  end
end
