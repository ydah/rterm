# frozen_string_literal: true

require "open3"

RSpec.describe "browser adapter asset smoke" do
  it "executes browser adapter rendering and link event paths in a minimal DOM" do
    node = required_command("node", strict: strict_browser_e2e?)

    stdout, stderr, status = Open3.capture3(node, "spec/fixtures/browser_adapter_smoke.js", chdir: Dir.pwd)

    expect(status).to be_success, stderr
    expect(stdout).to include("browser-adapter-smoke-ok")
  end

  def strict_browser_e2e?
    ENV["CI"] || ENV["RTERM_BROWSER_E2E"] == "1" || ENV["RTERM_STRICT_E2E"] == "1"
  end
end
