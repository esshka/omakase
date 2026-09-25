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
  # What RubyLLM.chat itself takes; every other option is a `with_*` call on the chat.
  CHAT_ARGUMENTS = %i[model provider protocol assume_model_exists context].freeze

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
    # will do — Executor::Subprocess is the reference: a child process, so a
    # timeout cannot take this one with it.
    def executor=(executor)
      @executor = callable!(executor, "executor")
    end

    def executor = @executor ||= Executor

    # How text becomes a vector, for Memory. Anything answering `call(text)`
    # will do; the model and its provider are RubyLLM's to configure.
    def embedder=(embedder)
      @embedder = callable!(embedder, "embedder")
    end

    def embedder = @embedder ||= ->(text) { RubyLLM.embed(text).vectors }

    # How an agent gets a chat when none was injected. Anything answering
    # `call(**options)` will do — one line in test_helper.rb keeps a whole suite
    # off the network, including the class-level calls a job makes.
    def chat_factory=(factory)
      @chat_factory = callable!(factory, "chat_factory")
    end

    def chat_factory = @chat_factory ||= method(:build_chat)

    # `caching: true`, `thinking: {effort: :high}`, `temperature: 0.2` become the
    # chat's own with_* calls. Caching is on unless you say `caching: false`: the
    # tool loop resends the whole chat on every step.
    def build_chat(**options)
      chat = RubyLLM.chat(**options.slice(*CHAT_ARGUMENTS))
      {caching: true, **options.except(*CHAT_ARGUMENTS)}.each do |name, value|
        setter = :"with_#{name}"
        raise Error, "unknown chat option #{name}: RubyLLM::Chat has no ##{setter}" unless chat.respond_to?(setter)

        keywords = chat.method(setter).parameters.any? { |kind, _| kind == :keyrest }
        case value
        when true then chat.public_send(setter)
        when Array then chat.public_send(setter, *value)
        when Hash then keywords ? chat.public_send(setter, **value) : chat.public_send(setter, value)
        else chat.public_send(setter, value)
        end
      end
      chat
    end

    # Every step, as it happens: a generation starts, model-written code runs,
    # an answer lands. Anything answering `call(event, **payload)` will do —
    # a logger, a tracer, a test. Nil, the default, costs nothing.
    def listener=(listener)
      @listener = callable!(listener, "listener")
    end

    attr_reader :listener

    def emit(event, **payload) = @listener&.call(event, **payload)

    private

    # Fail where the swap is made, not deep inside a generation.
    def callable!(object, name)
      return object if object.nil? || object.respond_to?(:call)

      raise Error, "#{name} must answer call, got #{object.class}"
    end
  end
end
