# frozen_string_literal: true

require_relative "lib/rterm/version"

Gem::Specification.new do |spec|
  spec.name = "rterm"
  spec.version = RTerm::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Ruby terminal emulator — a Ruby port of xterm.js core logic"
  spec.description = "A headless terminal emulator library for Ruby, providing ANSI/VT escape sequence parsing, " \
                     "terminal buffer management, and PTY integration. Based on xterm.js architecture."
  spec.homepage = "https://github.com/ydah/rterm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .idea/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
