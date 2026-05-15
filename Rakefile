# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

namespace :e2e do
  task :strict_env do
    ENV["RTERM_STRICT_E2E"] = "1"
  end

  desc "Run integration and browser smoke specs with strict external dependency checks"
  RSpec::Core::RakeTask.new(strict: :strict_env) do |task|
    task.pattern = [
      "spec/integration/**/*_spec.rb",
      "spec/browser_adapter/browser_adapter_real_browser_spec.rb"
    ]
  end
end

namespace :docs do
  desc "Generate YARD documentation"
  task :yard do
    begin
      require "yard"
    rescue LoadError
      abort "Install yard to generate documentation: gem install yard"
    end

    sh "yard doc"
  end
end

namespace :package do
  desc "Verify gem package contents before release"
  task :verify_contents do
    spec = Gem::Specification.load("rterm.gemspec")
    forbidden = spec.files.grep(%r{\A(?:spec|\.idea|\.github|tmp|pkg|doc)/})
    raise "Forbidden files in package: #{forbidden.join(', ')}" unless forbidden.empty?

    required = %w[
      lib/rterm.rb
      lib/rterm/browser_adapter.rb
      lib/rterm/browser_adapter/browser_adapter.css
      lib/rterm/browser_adapter/browser_adapter.js
      lib/rterm/browser_adapter/webgl_renderer.js
      README.md
      LICENSE.txt
    ]
    missing = required - spec.files
    raise "Missing required files from package: #{missing.join(', ')}" unless missing.empty?
  end
end

task default: :spec
