# frozen_string_literal: true

# Object-oriented agents: an agent is a Ruby object. Its methods are its tools,
# and the methods it *declares* but does not implement are written by an LLM.
require "json"
require "ruby_llm"
require "schematist"
require "stringio"
require "timeout"
require "zeitwerk"
require "yaml"

loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.ignore("#{__dir__}/omakase-agents.rb")
loader.inflector.inflect("mcp" => "MCP")
loader.setup

module Omakase
  Error = Class.new(StandardError)
  # The answer did not match the declared return type.
  ContractError = Class.new(Error)
  # The model or its provider failed. RubyLLM has already retried what it retries.
  ProviderError = Class.new(Error)

  class << self
    # Providers, keys, default model, timeouts, logging — all of it is RubyLLM's.
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

    # Where generated code runs. Anything answering `call(agent, code, timeout:)`
    # will do — swap in a subprocess or a container to get real isolation.
    attr_writer :executor

    def executor = @executor ||= Executor
  end
end
