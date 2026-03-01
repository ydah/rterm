# frozen_string_literal: true

RSpec.describe RTerm::Common::UnicodeHandler do
  subject(:handler) { described_class.new }

  describe "#char_width" do
    context "with ASCII characters" do
      it "returns 1 for printable ASCII" do
        expect(handler.char_width(0x41)).to eq(1)  # 'A'
        expect(handler.char_width(0x7A)).to eq(1)  # 'z'
        expect(handler.char_width(0x20)).to eq(1)  # space
        expect(handler.char_width(0x7E)).to eq(1)  # '~'
      end
    end

    context "with control characters" do
      it "returns 0 for C0 control characters (0x00-0x1F)" do
        expect(handler.char_width(0x00)).to eq(0)  # NUL
        expect(handler.char_width(0x01)).to eq(0)  # SOH
        expect(handler.char_width(0x0A)).to eq(0)  # LF
        expect(handler.char_width(0x0D)).to eq(0)  # CR
        expect(handler.char_width(0x1F)).to eq(0)
      end

      it "returns 0 for DEL (0x7F)" do
        expect(handler.char_width(0x7F)).to eq(0)
      end

      it "returns 0 for C1 control characters (0x80-0x9F)" do
        expect(handler.char_width(0x80)).to eq(0)
        expect(handler.char_width(0x9F)).to eq(0)
      end
    end

    context "with CJK Unified Ideographs" do
      it "returns 2 for CJK Unified Ideographs (U+4E00-U+9FFF)" do
        expect(handler.char_width(0x4E00)).to eq(2)  # first CJK
        expect(handler.char_width(0x4E2D)).to eq(2)  # 中
        expect(handler.char_width(0x9FFF)).to eq(2)  # last in range
      end
    end

    context "with Katakana" do
      it "returns 1 for half-width Katakana (U+FF61-U+FFDC)" do
        expect(handler.char_width(0xFF61)).to eq(1)
        expect(handler.char_width(0xFF9F)).to eq(1)
        expect(handler.char_width(0xFFDC)).to eq(1)
      end

      it "returns 2 for full-width Katakana (U+30A0-U+30FF)" do
        expect(handler.char_width(0x30A0)).to eq(2)
        expect(handler.char_width(0x30AB)).to eq(2)  # カ
        expect(handler.char_width(0x30FF)).to eq(2)
      end
    end

    context "with Emoji" do
      it "returns 2 for basic Emoji" do
        expect(handler.char_width(0x1F600)).to eq(2)  # 😀
        expect(handler.char_width(0x1F64F)).to eq(2)  # 🙏
        expect(handler.char_width(0x1F680)).to eq(2)  # 🚀
      end
    end

    context "with combining marks" do
      it "returns 0 for Combining Diacritical Marks (U+0300-U+036F)" do
        expect(handler.char_width(0x0300)).to eq(0)  # Combining grave
        expect(handler.char_width(0x0301)).to eq(0)  # Combining acute
        expect(handler.char_width(0x036F)).to eq(0)
      end
    end

    context "with zero-width characters" do
      it "returns 0 for zero-width space (U+200B)" do
        expect(handler.char_width(0x200B)).to eq(0)
      end

      it "returns 0 for zero-width joiner (U+200D)" do
        expect(handler.char_width(0x200D)).to eq(0)
      end

      it "returns 0 for BOM / FEFF" do
        expect(handler.char_width(0xFEFF)).to eq(0)
      end
    end

    context "with Hangul Syllables" do
      it "returns 2 for Hangul Syllables (U+AC00-U+D7A3)" do
        expect(handler.char_width(0xAC00)).to eq(2)  # 가
        expect(handler.char_width(0xD7A3)).to eq(2)
      end
    end

    context "with fullwidth Latin letters" do
      it "returns 2 for Fullwidth Forms (U+FF01-U+FF60)" do
        expect(handler.char_width(0xFF01)).to eq(2)  # ！
        expect(handler.char_width(0xFF21)).to eq(2)  # Ａ
        expect(handler.char_width(0xFF60)).to eq(2)
      end
    end

    context "with Fullwidth Signs" do
      it "returns 2 for Fullwidth Signs (U+FFE0-U+FFE6)" do
        expect(handler.char_width(0xFFE0)).to eq(2)
        expect(handler.char_width(0xFFE6)).to eq(2)
      end
    end

    context "with CJK Extensions" do
      it "returns 2 for CJK Extension B+ (U+20000-U+2FFFD)" do
        expect(handler.char_width(0x20000)).to eq(2)
        expect(handler.char_width(0x2FFFD)).to eq(2)
      end

      it "returns 2 for CJK Extension G+ (U+30000-U+3FFFD)" do
        expect(handler.char_width(0x30000)).to eq(2)
        expect(handler.char_width(0x3FFFD)).to eq(2)
      end
    end

    context "with variation selectors" do
      it "returns 0 for variation selectors (U+FE00-U+FE0F)" do
        expect(handler.char_width(0xFE00)).to eq(0)
        expect(handler.char_width(0xFE0F)).to eq(0)
      end
    end

    context "with Latin characters beyond ASCII" do
      it "returns 1 for Latin Extended characters" do
        expect(handler.char_width(0x00C0)).to eq(1)  # À
        expect(handler.char_width(0x00FF)).to eq(1)  # ÿ
      end
    end
  end

  describe "#wide?" do
    it "returns true for wide characters" do
      expect(handler.wide?(0x4E00)).to be true   # CJK
      expect(handler.wide?(0x30AB)).to be true   # Katakana
      expect(handler.wide?(0xAC00)).to be true   # Hangul
      expect(handler.wide?(0x1F600)).to be true  # Emoji
    end

    it "returns false for non-wide characters" do
      expect(handler.wide?(0x41)).to be false     # ASCII
      expect(handler.wide?(0x0300)).to be false   # Combining mark
      expect(handler.wide?(0x200B)).to be false   # Zero-width
      expect(handler.wide?(0x00)).to be false     # Control
    end
  end
end
