# frozen_string_literal: true

require_relative "lib/omakase/version"

Gem::Specification.new do |spec|
  spec.name = "omakase-agents"
  spec.version = Omakase::VERSION
  spec.authors = ["eugeny"]
  spec.email = ["esshka@gmail.com"]

  spec.summary = "Agents as plain Ruby objects."
  spec.description = <<~TEXT
    A light agent framework on top of RubyLLM. An agent is an object: its fields are state, its
    methods are what the model can call, and the methods it declares without a body are written by
    the model at runtime — the method name and prompt are the specification, the schema is the
    contract. The model acts by writing Ruby that runs on the agent itself.
  TEXT
  spec.homepage = "https://github.com/esshka/omakase"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + %w[README.md CHANGELOG.md LICENSE]
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby_llm", "~> 1.16"
  spec.add_dependency "schematist", "~> 1.1"
  spec.add_dependency "zeitwerk", "~> 2.7"
end
