# frozen_string_literal: true

RSpec.describe "RTerm::PTY compatibility" do
  it "exposes the specification class name as an alias" do
    expect(RTerm::PTY).to equal(RTerm::Pty)
  end
end
