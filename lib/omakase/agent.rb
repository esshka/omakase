# frozen_string_literal: true

module Omakase
  # Fields are state, methods are what the model can call, `generates` declares
  # the methods the model implements.
  class Agent
    # The generations this thread is inside, so one cannot re-enter itself.
    RUNNING = :omakase_running
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
      # The server opens on the first generate, not at class load.
      def mcp(name, **options) = MCP.defer(self, name, options)

      # A skill directory — a SKILL.md with YAML front matter. Its description
      # joins the agent's capabilities; its body arrives when the model asks.
      def skill(path) = Skills.attach(self, path)

      # Two more methods: one to save something, one to search it by meaning.
      # The store is a field, so it marshals with the agent and outlives the run.
      def memory
        describe "Save something worth remembering after this run"
        define_method(:remember) { |text| (@memory ||= Memory.new).remember(text) }
        describe "Search what you remember, by meaning; the closest few come back"
        define_method(:recall) { |query, limit: 5| (@memory ||= Memory.new).recall(query, limit:) }
      end

      # Documents the method defined next — the docstring Ruby does not have.
      def describe(text)
        @pending_description = text
      end

      # Without a prompt, the method name is the prompt. A block instead of a
      # string is a prompt read at call time, on the agent. `takes:` names the
      # keyword arguments, and then Ruby checks them.
      def generates(name, prompt = nil, takes: nil, returns: nil, strategy: nil, model: nil, &schema)
        # Redeclaring an inherited generation is how a subclass specialises one.
        # Landing on a method you wrote is not that, and would replace it unseen.
        if Capabilities.names(self).include?(name) && !generations.key?(name)
          raise Error, "#{self}##{name} is already a method — generates would replace it"
        end

        unless prompt.nil? || prompt.is_a?(String) || prompt.is_a?(Proc)
          raise Error, "#{self}##{name}: a prompt is a String or a block returning one, got #{prompt.class}"
        end

        generations[name] = Generation.new(
          name:,
          prompt: prompt || humanize(name),
          schema: Schema.define(returns:, &schema),
          strategy: Strategies.fetch(strategy || self.strategy),
          model:
        )
        define_generation_method(name, takes)
        define_singleton_method(name) { |**inputs| new.public_send(name, **inputs) }
      end

      def generations = @generations ||= {}

      def descriptions = @descriptions ||= {}

      def chat_options = @chat_options ||= {}

      private

      # Named inputs become a real signature, so a missing or misspelled argument
      # is an ArgumentError at the call rather than noise in a prompt — and the
      # model reads the names too, instead of `**inputs`.
      def define_generation_method(name, takes)
        return define_method(name) { |**inputs| generate(name, inputs) } if takes.nil?

        keywords = Array(takes)
        bad = [name.to_s.chomp("?").chomp("!"), *keywords].reject { |word| /\A[a-z_]\w*\z/.match?(word.to_s) }
        raise Error, "#{self}##{name}: takes: needs plain keyword names, got #{bad.inspect}" if bad.any?

        class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{name}(#{keywords.map { |key| "#{key}:" }.join(", ")}, with: nil)
            inputs = {#{keywords.map { |key| "#{key}: #{key}" }.join(", ")}}
            inputs[:with] = with unless with.nil?
            generate(:#{name}, inputs)
          end
        RUBY
      end

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

    # A fresh conversation per call — two threads calling one agent must not
    # share a mutable chat. What carries between calls is the object's own state.
    # Overrides land on top of the class's options; an injected chat ignores them.
    def chat(**overrides) = @chat || Omakase.chat_factory.call(**self.class.chat_options.merge(overrides))

    # That state, as the model should read it: rebuilt on every call, and added
    # to the class's instructions. Override it to remember anything.
    def context = nil

    # Resuming a run is loading the object back, so an agent marshals like any
    # other Ruby object — minus the live chat, which is rebuilt on demand.
    def marshal_dump = (instance_variables - [:@chat]).to_h { |name| [name, instance_variable_get(name)] }

    def marshal_load(state) = state.each { |name, value| instance_variable_set(name, value) }

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
      (args.size <= 1) ? args.first : args
    end

    alias_method :pp, :p

    private

    def omakase_output = Thread.current[Executor::OUTPUT] || $stdout

    def generate(name, inputs)
      generation = self.class.generations.fetch(name)
      running = (Thread.current[RUNNING] ||= [])
      key = [object_id, name]

      # Generated code can see this method and call it. Each nested call opens its
      # own chat with its own tool budget, so the budget would bound nothing.
      raise Error, "#{self.class}##{name} is already running — it cannot call itself" if running.include?(key)

      running.push(key)
      begin
        MCP.ensure(self.class)
        Omakase.emit(:generation, agent: self, name:, inputs:)
        value = generation.strategy.call(Request.new(agent: self, generation:, inputs:))
        Omakase.emit(:answer, agent: self, name:, value:)
        value
      rescue RubyLLM::Error, RubyLLM::ConfigurationError, RubyLLM::ModelNotFoundError => e
        raise ProviderError, "#{self.class}##{name}: #{e.message}"
      ensure
        running.delete(key)
      end
    end
  end
end
