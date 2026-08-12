# frozen_string_literal: true

# Object-oriented agents: an agent is a Ruby object. Its methods are its tools,
# and the methods it *declares* but does not implement are written by an LLM.
require "ruby_llm"
require "schematist"
require "stringio"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.setup

module Omakase
  Error = Class.new(StandardError)

  class << self
    # Providers, keys, default model, logging — all of it is RubyLLM's.
    def configure(&) = RubyLLM.configure(&)

    # Reads every provider credential RubyLLM knows from the environment:
    # ANTHROPIC_API_KEY, OPENROUTER_API_KEY, OLLAMA_API_BASE, VERTEXAI_PROJECT_ID, …
    def configure_from_env(env = ENV)
      configure do |config|
        provider_options.each do |option|
          value = env[option.to_s.upcase]
          config.public_send(:"#{option}=", value) if value
        end
      end
    end

    def provider_options
      slugs = RubyLLM::Provider.providers.keys
      RubyLLM::Configuration.options.select do |option|
        slugs.any? { |slug| option.to_s.start_with?("#{slug}_") }
      end
    end
  end
end
