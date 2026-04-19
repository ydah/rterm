# frozen_string_literal: true

RSpec.describe RTerm::ConPTY do
  it "reports platform support" do
    expect(described_class.supported?).to eq(Gem.win_platform?)
  end

  it "raises a platform error outside Windows" do
    skip "ConPTY is only expected to raise this boundary error off Windows" if described_class.supported?

    expect { described_class.new(command: "cmd.exe") }
      .to raise_error(RTerm::ConPTY::UnsupportedPlatformError, /only available on Windows/)
  end
end
