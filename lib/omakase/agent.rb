# frozen_string_literal: true

module Omakase
  # Fields are state, methods are what the model can call, `generates` declares
  # the methods the model implements.
  class Agent
    class << self
      # The model and any RubyLLM chat option. Naming a provider takes the model
      # id on trust, since providers like OpenRouter or Ollama serve ids that are
      # not in RubyLLM's registry.
      def model(id = nil, **options)
        return chat_options if id.nil? && options.empty?

        options = {assume_model_exists: true, **options} if options[:provider]
        @chat_options = {model: id, **options}.compact
      end

      def instructions(text = nil)
        return @instructions.to_s if text.nil?

        @instructions = text
      end

      def strategy(name = nil)
        return @strategy || :code_act if name.nil?

        @strategy = name
      end

      # An MCP server's tools, as methods on the agent. Options are passed to
      # `ruby_llm-mcp` verbatim: `mcp :files, transport_type: :stdio, config: {command: "npx", …}`.
      def mcp(name, **options)
        require "ruby_llm/mcp"
        MCP.attach(self, RubyLLM::MCP.add_client(name: name.to_s, **options))
      end

      # A skill directory — a SKILL.md with YAML front matter. Its description
      # joins the agent's capabilities; its body arrives when the model asks.
      def skill(path) = Skills.attach(self, path)
      # Documents the method defined next — the docstring Ruby does not have.
      def describe(text)
        @pending_description = text
      end

      # Without a prompt, the method name is the prompt.
      def generates(name, prompt = nil, returns: nil, strategy: nil, &schema)
        generations[name] = Generation.new(
          name:,
          prompt: prompt || humanize(name),
          schema: Schema.define(returns:, &schema),
          strategy: Strategies.fetch(strategy || self.strategy)
        )
        define_method(name) { |**inputs| generate(name, inputs) }
        define_singleton_method(name) { |**inputs| new.public_send(name, **inputs) }
      end

      def generations = @generations ||= {}

      def descriptions = @descriptions ||= {}

      def chat_options = @chat_options ||= {}

      private

      def humanize(name)
        text = name.to_s.tr("_", " ").capitalize
        text.end_with?("?", "!") ? text : "#{text}."
      end

      def method_added(name)
        super
        descriptions[name] = @pending_description if @pending_description
        @pending_description = nil
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@chat_options, chat_options.dup)
        subclass.instructions(instructions) unless instructions.empty?
        subclass.strategy(@strategy) if @strategy
        subclass.generations.merge!(generations)
        subclass.descriptions.merge!(descriptions)
      end
    end

    # `chat:` injects a prepared RubyLLM::Chat — the seam for tests.
    def initialize(chat: nil)
      @chat = chat
    end

    # A fresh conversation per call.
    def chat = @chat || RubyLLM.chat(**self.class.chat_options)

    # For generated code meeting an object whose type it does not know.
    def doc(object) = puts(Doc.of(object))

    # How generated code answers: with the value itself.
    def finish(value) = throw(Executor::RESULT, value)

    # Printing from generated code goes to the observation, not to the process's
    # stdout — and the buffer is per thread, so concurrent agents stay separate.
    def puts(*args) = omakase_output.puts(*args)

    def print(*args) = omakase_output.print(*args)

    def p(*args)
      args.each { |arg| omakase_output.puts(arg.inspect) }
      args.size <= 1 ? args.first : args
    end

    alias_method :pp, :p

    private

    def omakase_output = Thread.current[Executor::OUTPUT] || $stdout

    def generate(name, inputs)
      generation = self.class.generations.fetch(name)
      generation.strategy.call(Request.new(agent: self, generation:, inputs:))
    rescue RubyLLM::Error, RubyLLM::ConfigurationError, RubyLLM::ModelNotFoundError => e
      raise ProviderError, "#{self.class}##{name}: #{e.message}"
    end
  end
end
