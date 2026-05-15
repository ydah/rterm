# frozen_string_literal: true

require "open3"

RSpec.describe "browser adapter asset smoke" do
  it "executes browser adapter rendering and link event paths in a minimal DOM" do
    node = `command -v node`.strip
    skip "node not installed" if node.empty?

    stdout, stderr, status = Open3.capture3(node, "spec/fixtures/browser_adapter_smoke.js", chdir: Dir.pwd)

    expect(status).to be_success, stderr
    expect(stdout).to include("browser-adapter-smoke-ok")
  end
end
