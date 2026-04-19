# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

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

    required = %w[lib/rterm.rb README.md LICENSE.txt]
    missing = required - spec.files
    raise "Missing required files from package: #{missing.join(', ')}" unless missing.empty?
  end
end

task default: :spec
