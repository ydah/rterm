# frozen_string_literal: true

require "open3"

RSpec.describe "browser adapter real browser smoke" do
  it "renders DOM links and raster canvas frames in a browser when Playwright is available" do
    node = `command -v node`.strip
    skip "node not installed" if node.empty?

    stdout, stderr, status = Open3.capture3(node, "spec/fixtures/browser_adapter_playwright_smoke.js", chdir: Dir.pwd)

    if stdout.include?("browser-adapter-playwright-missing") || stdout.include?("browser-adapter-playwright-unavailable")
      raise stdout.strip if strict_browser_e2e?

      skip stdout.strip
    end

    expect(status).to be_success, stderr
    expect(stdout).to include("browser-adapter-playwright-ok")
  end

  def strict_browser_e2e?
    ENV["RTERM_BROWSER_E2E"] == "1" || ENV["RTERM_STRICT_E2E"] == "1"
  end
end
