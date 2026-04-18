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
end
