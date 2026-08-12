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

    private

    def generate(name, inputs)
      generation = self.class.generations.fetch(name)
      generation.strategy.call(Request.new(agent: self, generation:, inputs:))
    end
  end
end
