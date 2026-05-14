# frozen_string_literal: true

RSpec.describe RTerm::ServiceContainer do
  it "registers and retrieves service instances" do
    container = described_class.new
    service = Object.new

    container.register(RTerm::Services::LOG_SERVICE, service)

    expect(container.get(RTerm::Services::LOG_SERVICE)).to equal(service)
    expect(container).to have_service(RTerm::Services::LOG_SERVICE)
  end

  it "lazily evaluates factories once" do
    container = described_class.new
    calls = 0

    container.register(:service, -> { calls += 1 })

    expect(container.get(:service)).to eq(1)
    expect(container.get(:service)).to eq(1)
    expect(calls).to eq(1)
  end

  it "raises for missing services" do
    container = described_class.new

    expect { container.get(:missing) }.to raise_error(RTerm::ServiceContainer::ServiceNotFound)
  end

  it "registers core log, char size, and OSC link services" do
    terminal = RTerm::Terminal.new(log_level: :warn)
    services = terminal.internal.services

    expect(services.get(RTerm::Services::LOG_SERVICE).debug("ignored")).to be_nil
    expect(services.get(RTerm::Services::LOG_SERVICE).warn("kept")[:message]).to eq("kept")
    expect(services.get(RTerm::Services::CHAR_SIZE_SERVICE).measure(width: 8, height: 16)).to eq(
      { width: 8.0, height: 16.0, source: :measured }
    )

    terminal.write("\e]8;id=1;https://example.com\a")
    expect(services.get(RTerm::Services::OSC_LINK_SERVICE).active_link).to eq(
      { params: "id=1", uri: "https://example.com" }
    )
  end

  it "estimates character size from terminal options" do
    service = RTerm::Services::CharSizeService.new

    size = service.estimate_from_options(font_size: 20, line_height: 1.2, letter_spacing: 1)

    expect(size).to eq(width: 13.0, height: 24.0, source: :estimated)
    expect(service).to be_estimated
    expect(service).to be_ready
  end
end
