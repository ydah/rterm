# frozen_string_literal: true

RSpec.describe "gem package contents" do
  it "keeps generated, test, and IDE files out of the gem" do
    spec = Gem::Specification.load(File.expand_path("../../rterm.gemspec", __dir__))

    expect(spec.files).to include("lib/rterm.rb", "README.md", "LICENSE.txt")
    expect(spec.files.grep(%r{\A(?:spec|\.idea|\.github|tmp|pkg|doc)/})).to be_empty
  end
end
