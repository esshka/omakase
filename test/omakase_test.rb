# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "active_model"
require_relative "../lib/omakase"

FakeChat = Omakase::FakeChat

class FeedbackAgent < Omakase::Agent
  instructions "You analyze customer feedback."
  strategy :predict

  generates :sentiment_of, "Classify the sentiment in one word."

  generates :analyze do
    string :sentiment, enum: %w[positive negative]
    array :topics, of: :string
  end
end

class InventoryAgent < Omakase::Agent
  instructions "You check inventory."

  def initialize(stock, **options)
    super(**options)
    @stock = stock
  end

  describe "Units of an item on hand"
  def stock_of(item) = @stock.fetch(item, 0)

  generates :total_stock, "Total stock for the given items.", returns: :integer
end

Ticket = Struct.new(:id, :severity)

# The shape every Rails object has: it knows whether it is well-formed.
class Draft
  include ActiveModel::Model

  attr_accessor :title, :body
  validates :title, presence: true
end

class DraftAgent < Omakase::Agent
  instructions "You draft posts."

  generates :draft, "Draft a post about the topic.", returns: Draft
end

class TicketAgent < Omakase::Agent
  instructions "You file tickets."

  generates :file, "File a ticket for the message.", returns: Ticket
end

class LoopAgent < Omakase::Agent
  generates :work, "Do the work.", returns: :integer
end

class PredictTest < Minitest::Test
  def test_a_scalar_return_type_unwraps_to_the_value
    chat = FakeChat.new { {"result" => "positive"} }

    assert_equal "positive", FeedbackAgent.new(chat:).sentiment_of(text: "love it")
    assert_equal [:result], chat.schema.properties.keys
    assert_includes chat.instructions.first, "You analyze customer feedback."
    assert_includes chat.instructions.first, "Answer as JSON matching this schema"
    assert_includes chat.tasks.first, %(- text: "love it")
  end

  def test_a_schema_block_returns_the_whole_object_with_symbol_keys
    chat = FakeChat.new { {"sentiment" => "negative", "topics" => ["shipping"]} }

    assert_equal({sentiment: "negative", topics: ["shipping"]},
      FeedbackAgent.new(chat:).analyze(text: "slow"))
    assert_equal %i[sentiment topics], chat.schema.properties.keys
  end

  def test_with_sends_attachments_instead_of_rendering_them
    chat = FakeChat.new { {"result" => "a cat"} }
    agent = Class.new(Omakase::Agent) do
      strategy :predict
      generates :caption, "Describe the photo."
    end.new(chat:)

    assert_equal "a cat", agent.caption(question: "what animal?", with: "photo.jpg")
    assert_equal ["photo.jpg"], chat.attachments
    assert_includes chat.tasks.first, %(- question: "what animal?")
    refute_includes chat.tasks.first, "photo.jpg"
  end

  def test_an_off_contract_answer_gets_one_correction_turn
    replies = ["prose, not JSON", {"result" => "positive"}]
    chat = FakeChat.new { replies.shift }

    assert_equal "positive", FeedbackAgent.new(chat:).sentiment_of(text: "love it")
    assert_includes chat.tasks.last, "expected JSON matching"
    assert_includes chat.tasks.last, "Answer again as JSON"
  end

  def test_a_second_bad_answer_is_raised
    chat = FakeChat.new { "just some prose" }

    error = assert_raises(Omakase::Error) { FeedbackAgent.new(chat:).sentiment_of(text: "x") }
    assert_match(/expected JSON matching .*got "just some prose"/, error.message)
  end
end

class CodeActTest < Minitest::Test
  # The model that never calls finish: it works, then answers under the schema.
  def chat_running(code, observed:, answer:)
    FakeChat.new do |fake|
      next answer if fake.schema

      observed << fake.run(code)
      "done"
    end
  end

  def observe(code, stock: {})
    observed = []
    chat = chat_running(code, observed:, answer: {"result" => 0})
    InventoryAgent.new(stock, chat:).total_stock(items: [])
    observed.first
  end

  def test_generated_code_runs_against_the_agent_and_its_state
    observed = []
    chat = chat_running("stock_of('apple') + stock_of('pear')", observed:, answer: {"result" => 7})

    assert_equal 7, InventoryAgent.new({"apple" => 3, "pear" => 4}, chat:).total_stock(items: %w[apple pear])
    assert_equal ["=> 7"], observed
    assert_equal "ruby", chat.tools.first.name
    assert_includes chat.tasks.last, "Work done:\ndone"
  end

  def test_printed_output_comes_back_as_the_observation
    assert_equal "3\n=> nil", observe("puts stock_of('apple'); nil", stock: {"apple" => 3})
  end

  def test_a_failing_line_is_named_so_the_model_can_fix_it
    observation = observe("total = 1\nstock_of\n")

    assert_match(/ArgumentError/, observation)
    assert_includes observation, "line 2: stock_of"
  end

  def test_doc_prints_what_an_unknown_object_offers
    observation = observe(%(doc(Struct.new(:ticker, :shares).new("NVDA", 100))))

    assert_includes observation, "ticker()"
    assert_includes observation, "shares()"
    refute_includes observation, "each_with_object"
  end

  def test_a_record_reads_as_its_own_methods_and_the_values_it_holds
    record = Class.new do
      def self.to_s = "Order"
      def attributes = {"id" => 1, "email" => "ada@example.com"}
      def total = 39.9
    end.new

    assert_equal ["Order", "  attributes()", "  total()", %(  id = 1), %(  email = "ada@example.com")].join("\n"),
      Omakase::Doc.of(record)
  end

  def test_a_class_reads_as_what_one_of_its_objects_would_have
    model = Class.new do
      def self.to_s = "Order"
      def self.column_names = %w[id email]

      def total = 39.9
    end

    assert_equal ["Order", "  total()", "  id", "  email"].join("\n"), Omakase::Doc.of(model)
  end

  def test_finish_answers_in_one_turn_with_the_computed_value
    chat = FakeChat.new do |fake|
      fake.run("finish(stock_of(:apple) + stock_of(:pear))")
      "done"
    end

    assert_equal 7, InventoryAgent.new({apple: 3, pear: 4}, chat:).total_stock(items: [])
    assert_equal 1, chat.tasks.size
    assert_nil chat.schema
  end

  def test_an_off_contract_finish_is_corrected_inside_the_loop
    rejected = nil
    chat = FakeChat.new do |fake|
      rejected = fake.run(%(finish("three")))
      fake.run("finish(3)")
      "done"
    end

    assert_equal 3, InventoryAgent.new({}, chat:).total_stock(items: [])
    assert_includes rejected, %(finish rejected: expected <integer>, got "three")
  end

  def test_an_invalid_object_is_refused_and_the_model_fixes_it_in_the_loop
    rejected = nil
    chat = FakeChat.new do |fake|
      rejected = fake.run(%(finish(Draft.new(body: "a post about mugs"))))
      fake.run(%(finish(Draft.new(title: "Mugs", body: "a post about mugs"))))
      "done"
    end

    draft = DraftAgent.new(chat:).draft(topic: "mugs")

    assert_equal "Mugs", draft.title
    assert_includes rejected, "finish rejected: Draft is invalid: Title can't be blank"
  end

  def test_an_object_that_cannot_say_it_is_valid_is_taken_as_it_is
    chat = FakeChat.new do |fake|
      fake.run(%(finish(Ticket.new("A-1", "high"))))
      "done"
    end

    assert_equal "A-1", TicketAgent.new(chat:).file(message: "broken").id
  end

  def test_a_ruby_class_return_type_hands_back_the_object_itself
    chat = FakeChat.new do |fake|
      fake.run(%(finish(Ticket.new("A-1", "high"))))
      "done"
    end

    ticket = TicketAgent.new(chat:).file(message: "it arrived cracked")

    assert_instance_of Ticket, ticket
    assert_equal "A-1", ticket.id
  end

  def test_a_class_return_type_that_is_never_finished_fails_loudly
    chat = FakeChat.new { "I have decided, but I will not call finish." }

    error = assert_raises(Omakase::ContractError) { TicketAgent.new(chat:).file(message: "cracked") }
    assert_equal "file: the model never called finish(Ticket.new(id:, severity:))", error.message
  end

  def test_the_instructions_name_the_shape_finish_must_take
    chat = FakeChat.new { |fake| fake.schema ? {"result" => 0} : "done" }
    InventoryAgent.new({}, chat:).total_stock(items: [])

    assert_includes chat.instructions.first, "finish(<integer>)"
  end

  def test_the_tool_call_budget_bounds_the_loop
    tool = Omakase::Tools::Ruby.new(InventoryAgent.new({}), Omakase::Schema.define(returns: :integer), budget: 2)

    2.times { assert_equal "=> 1", tool.execute(code: "1") }
    assert_match(/No tool calls left/, tool.execute(code: "1"))
    assert_instance_of RubyLLM::Tool::Halt, tool.execute(code: "1")
  end

  def test_instructions_list_the_agents_methods_but_not_the_one_being_written
    chat = FakeChat.new { |fake| fake.schema ? {"result" => 0} : "done" }
    InventoryAgent.new({}, chat:).total_stock(items: [])

    assert_includes chat.instructions.first, "You check inventory."
    assert_includes chat.instructions.first, "- stock_of(item) — Units of an item on hand"
    refute_includes chat.instructions.first, "total_stock"
  end
end

class ReliabilityTest < Minitest::Test
  def setup = @agent = InventoryAgent.new({"apple" => 3})

  def test_printing_is_per_thread_so_concurrent_agents_stay_separate
    outputs = 2.times.map do |i|
      Thread.new { Omakase::Executor.call(@agent, "puts #{i}; nil") }
    end.map(&:value)

    assert_equal ["0\n=> nil", "1\n=> nil"], outputs
  end

  def test_a_generation_cannot_call_itself
    refused = nil
    chat = FakeChat.new do |fake|
      refused = fake.run("work(task: 'again')")
      fake.run("finish(1)")
      "done"
    end
    agent = LoopAgent.new(chat:)

    assert_equal 1, agent.work(task: "start")
    assert_includes refused, "LoopAgent#work is already running"
    assert_empty Thread.current[Omakase::Agent::RUNNING] # nothing held once the run ends
  end

  def test_generated_code_cannot_run_forever
    observation = Omakase::Executor.call(@agent, "sleep 5", timeout: 0.05)

    assert_match(/Timeout::Error/, observation)
  end

  def test_what_was_printed_before_finish_is_not_lost
    answer = Omakase::Executor.call(@agent, %(puts "looked it up"\nfinish(3)))

    assert_equal 3, answer.value
    assert_equal "looked it up", answer.printed
  end

  def test_the_executor_is_swappable
    stub = Object.new
    def stub.call(_agent, code, timeout:) = Omakase::Executor::Answer.new(value: code.length)
    tool = Omakase::Tools::Ruby.new(@agent, Omakase::Schema.define(returns: :integer), executor: stub)

    tool.execute(code: "abc")

    assert_equal 3, tool.answer.value
  end

  def test_a_declaration_cannot_ask_for_two_contracts
    error = assert_raises(Omakase::Error) { Omakase::Schema.define(returns: :integer) { string :city } }

    assert_match(/two different contracts/, error.message)
  end

  def test_a_generation_cannot_silently_replace_a_method_you_wrote
    error = assert_raises(Omakase::Error) do
      Class.new(Omakase::Agent) do
        def total = 42
        generates :total
      end
    end

    assert_match(/already a method/, error.message)
  end

  def test_a_subclass_may_still_respecialise_an_inherited_generation
    parent = Class.new(Omakase::Agent) { generates :answer, "the parent prompt" }
    child = Class.new(parent) { generates :answer, "the child prompt" }

    assert_equal "the child prompt", child.generations[:answer].prompt
  end

  def test_a_seam_that_cannot_be_called_is_refused_where_it_is_set
    error = assert_raises(Omakase::Error) { Omakase.executor = "not callable" }

    assert_equal "executor must answer call, got String", error.message
    assert_raises(Omakase::Error) { Omakase.listener = 42 }
    assert_raises(Omakase::Error) { Omakase.chat_factory = 42 }
  ensure
    Omakase.executor = nil
  end

  def test_the_chat_factory_keeps_a_suite_off_the_network
    built = []
    Omakase.chat_factory = lambda do |**options|
      built << options
      FakeChat.new { {"result" => "positive"} }
    end

    # The class-level form is what a job calls, and it injects no chat of its own.
    assert_equal "positive", FeedbackAgent.sentiment_of(text: "love it")
    assert_equal [{}], built

    Class.new(FeedbackAgent) { model "small-model" }.sentiment_of(text: "again")

    assert_equal [{}, {model: "small-model"}], built # the class's chat options reach the factory
  ensure
    Omakase.chat_factory = nil
  end

  def test_an_injected_chat_still_wins_over_the_factory
    Omakase.chat_factory = ->(**) { raise "the factory should not be reached" }

    assert_equal "mixed", FeedbackAgent.new(chat: FakeChat.new { {"result" => "mixed"} }).sentiment_of(text: "eh")
  ensure
    Omakase.chat_factory = nil
  end

  def test_an_executor_that_breaks_its_contract_does_not_reach_the_model
    stub = Object.new
    def stub.call(_agent, _code, timeout:) = {not: :an_observation}
    tool = Omakase::Tools::Ruby.new(@agent, Omakase::Schema.define(returns: :integer), executor: stub)

    error = assert_raises(Omakase::Error) { tool.execute(code: "1") }

    assert_match(/must return a String or Executor::Answer, got Hash/, error.message)
  end

  def test_provider_failures_arrive_as_one_error_type
    chat = FakeChat.new { raise RubyLLM::RateLimitError.new(nil, "slow down") }

    error = assert_raises(Omakase::ProviderError) { FeedbackAgent.new(chat:).sentiment_of(text: "x") }
    assert_match(/FeedbackAgent#sentiment_of/, error.message)
  end

  # FakeChat stands in for RubyLLM::Chat in every test here, so it is the one thing
  # a green suite cannot vouch for: if the real chat moves, nothing else would notice.
  def test_the_fake_chat_still_stands_in_for_the_real_one
    fake = Omakase::FakeChat.instance_methods(false)

    %i[with_instructions with_schema with_tool ask].each do |name|
      assert_includes fake, name
      assert RubyLLM::Chat.method_defined?(name), "RubyLLM::Chat##{name} is gone"
    end
    assert_includes RubyLLM::Chat.instance_method(:ask).parameters, [:key, :with]
  end
end

class DslTest < Minitest::Test
  def test_the_method_name_is_the_prompt_when_none_is_given
    assert_equal "Analyze.", FeedbackAgent.generations[:analyze].prompt
  end

  def test_a_block_prompt_is_read_at_call_time_on_the_agent
    translator = Class.new(FeedbackAgent) do
      def initialize(language, **options)
        super(**options)
        @language = language
      end

      generates :translate, -> { "Translate to #{@language}." }
    end
    chat = FakeChat.new { {"result" => "hola"} }

    assert_equal "hola", translator.new("Spanish", chat:).translate(text: "hi")
    assert_includes chat.tasks.first, "Translate to Spanish."
  end

  def test_a_prompt_that_is_neither_a_string_nor_a_block_is_refused
    error = assert_raises(Omakase::Error) { Class.new(Omakase::Agent) { generates :answer, :the_prompt } }

    assert_match(/a prompt is a String or a block/, error.message)
  end

  def test_named_inputs_are_a_signature_ruby_checks
    agent_class = Class.new(Omakase::Agent) do
      strategy :predict
      generates :decide, "Decide.", takes: %i[email complaint], returns: :string
    end
    chat = FakeChat.new { {"result" => "refunded"} }

    assert_equal "refunded", agent_class.new(chat:).decide(email: "ada@example.com", complaint: "cracked")
    assert_raises(ArgumentError) { agent_class.new(chat:).decide(email: "ada@example.com") }
    assert_raises(ArgumentError) { agent_class.new(chat:).decide(email: "a", complaint: "b", emial: "typo") }
    assert_equal "decide(email:, complaint:, with:) — Decide.", Omakase::Capabilities.of(agent_class).first
  end

  def test_named_inputs_that_are_not_identifiers_are_refused_where_they_are_declared
    error = assert_raises(Omakase::Error) do
      Class.new(Omakase::Agent) { generates :answer, takes: ["not an identifier"] }
    end

    assert_match(/plain keyword names/, error.message)
  end

  def test_a_generation_can_name_its_own_model
    agent_class = Class.new(Omakase::Agent) do
      strategy :predict
      generates :quick, "Quick.", model: "small-model"
    end
    chat = FakeChat.new { {"result" => "ok"} }
    agent = agent_class.new
    overrides = nil
    agent.define_singleton_method(:chat) { |**options|
      overrides = options
      chat
    }

    assert_equal "ok", agent.quick
    assert_equal({model: "small-model"}, overrides)
  end

  def test_the_listener_hears_generations_code_and_answers
    events = []
    Omakase.listener = ->(event, **payload) { events << [event, payload] }

    chat = FakeChat.new { {"result" => "positive"} }
    FeedbackAgent.new(chat:).sentiment_of(text: "love it")
    tool = Omakase::Tools::Ruby.new(InventoryAgent.new({"apple" => 3}), Omakase::Schema.define(returns: :integer))
    tool.execute(code: "stock_of('apple')")

    assert_equal %i[generation answer ruby], events.map(&:first)
    assert_equal :sentiment_of, events[0].last[:name]
    assert_equal({text: "love it"}, events[0].last[:inputs])
    assert_equal "positive", events[1].last[:value]
    assert_equal "=> 3", events[2].last[:outcome]
  ensure
    Omakase.listener = nil
  end

  def test_the_trace_prints_each_step_for_a_human
    io = StringIO.new
    Omakase.listener = Omakase::Trace.new(io:)

    chat = FakeChat.new { {"result" => "positive"} }
    FeedbackAgent.new(chat:).sentiment_of(text: "love it")
    tool = Omakase::Tools::Ruby.new(InventoryAgent.new({"apple" => 3}), Omakase::Schema.define(returns: :integer))
    tool.execute(code: "stock_of('apple')")

    assert_includes io.string, "→ FeedbackAgent#sentiment_of"
    assert_includes io.string, %(text: "love it")
    assert_includes io.string, "← FeedbackAgent#sentiment_of"
    assert_includes io.string, "· ruby"
    assert_includes io.string, "stock_of('apple')"
    assert_includes io.string, "=> 3"
  ensure
    Omakase.listener = nil
  end

  def test_generation_methods_are_callable_on_the_class
    agent = Class.new(FeedbackAgent) do
      generates :answer
      def chat = FakeChat.new { {"result" => "42"} }
    end

    assert_equal "42", agent.answer(question: "life")
  end

  def test_strategies_resolve_by_name_and_reject_unknown_ones
    assert_equal Omakase::Strategies::CodeAct, Omakase::Strategies.fetch(:code_act)
    assert_raises(Omakase::Error) { Omakase::Strategies.fetch(:telepathy) }
  end

  def test_a_method_can_override_the_agents_strategy
    assert_equal Omakase::Strategies::Predict, FeedbackAgent.generations[:analyze].strategy
    assert_equal Omakase::Strategies::CodeAct, InventoryAgent.generations[:total_stock].strategy
  end

  def test_subclasses_inherit_configuration_and_generations
    subclass = Class.new(FeedbackAgent) { generates :summarize }

    assert_equal "You analyze customer feedback.", subclass.instructions
    assert_includes subclass.generations.keys, :analyze
    refute_includes FeedbackAgent.generations.keys, :summarize
  end

  def test_naming_a_provider_takes_the_model_id_on_trust
    agent = Class.new(Omakase::Agent) { model "meta/some-model", provider: :openrouter }

    assert_equal({model: "meta/some-model", provider: :openrouter, assume_model_exists: true},
      agent.chat_options)
  end

  def test_provider_credentials_are_read_from_the_environment
    Omakase.configure_from_env({"OPENROUTER_API_KEY" => "from-env", "OLLAMA_API_BASE" => "http://localhost:11434"})

    assert_equal "from-env", RubyLLM.config.openrouter_api_key
    assert_equal "http://localhost:11434", RubyLLM.config.ollama_api_base
  ensure
    RubyLLM.config.openrouter_api_key = nil
    RubyLLM.config.ollama_api_base = nil
  end

  def test_a_ruby_class_return_type_needs_generated_code
    error = assert_raises(Omakase::Error) { Omakase::Schema.define(returns: Ticket).definition }

    assert_match(/needs the :code_act strategy/, error.message)
  end

  def test_only_scalars_are_accepted_as_shorthand_return_types
    error = assert_raises(Omakase::Error) { Omakase::Schema.define(returns: :order) }

    assert_match(/returns: must be one of/, error.message)
  end
end

class McpTest < Minitest::Test
  # Stands in for a RubyLLM::MCP client and its tools.
  Tool = Struct.new(:name, :description, :params_schema, :outcome) do
    def execute(**arguments) = outcome.call(arguments)
  end

  def client(tool) = Struct.new(:tools).new([tool])

  def tool(**overrides)
    Tool.new(
      name: "read-file",
      description: "Read a file\n  from disk.",
      params_schema: {"type" => "object", "properties" => {"path" => {"type" => "string"}}, "required" => ["path"]},
      outcome: ->(arguments) { "contents of #{arguments[:path]}" },
      **overrides
    )
  end

  def agent_with(tool)
    Class.new(Omakase::Agent) { generates :summary }.tap { |klass| Omakase::MCP.attach(klass, client(tool)) }
  end

  def test_a_tool_becomes_a_method_the_generated_code_can_call
    agent = agent_with(tool).new

    assert_equal "contents of /tmp/a.txt", agent.read_file(path: "/tmp/a.txt")
  end

  def test_the_capability_line_carries_the_description_and_the_arguments
    entry = Omakase::Capabilities.of(agent_with(tool), except: :summary).first

    assert_equal "read_file(**arguments) — Read a file from disk. Arguments — path: string (required)", entry
  end

  def test_a_tool_that_shadows_an_existing_capability_is_refused
    agent = Class.new(Omakase::Agent) { def read_file(path) = File.read(path) }

    error = assert_raises(Omakase::Error) { Omakase::MCP.attach(agent, client(tool)) }
    assert_match(/already has #read_file/, error.message)
  end

  def test_arguments_the_model_left_out_are_not_sent
    agent = agent_with(tool(outcome: ->(arguments) { arguments.keys.inspect })).new

    assert_equal "[:path]", agent.read_file(path: "/tmp/a.txt", limit: nil)
  end

  def test_a_failed_call_raises_where_the_model_can_see_it
    agent = agent_with(tool(outcome: ->(_) { {error: "no such file"} })).new

    observation = Omakase::Executor.call(agent, %(read_file(path: "nope")))

    assert_includes observation, "Omakase::Error: no such file"
  end
end

class SkillsTest < Minitest::Test
  SKILL = <<~MD
    ---
    name: ruby-style
    description: How this codebase writes Ruby. Use before editing any .rb file.
    ---

    Prefer endless methods for one-liners.
  MD

  def with_skill
    Dir.mktmpdir do |root|
      directory = File.join(root, "ruby-style")
      Dir.mkdir(directory)
      File.write(File.join(directory, "SKILL.md"), SKILL)
      yield Class.new(Omakase::Agent) { skill directory }
    end
  end

  def test_the_description_is_a_capability_and_the_body_is_what_the_call_returns
    with_skill do |agent|
      assert_equal ["ruby_style() — How this codebase writes Ruby. Use before editing any .rb file."],
        Omakase::Capabilities.of(agent)
      assert_includes agent.new.ruby_style, "Prefer endless methods for one-liners."
    end
  end

  def test_the_body_says_where_the_skills_own_files_are
    with_skill { |agent| assert_match(%r{Files for this skill are in .*/ruby-style\.}, agent.new.ruby_style) }
  end
end

class ContextTest < Minitest::Test
  # Remembering is the object's job: what happened is state, and state is prompt.
  class InterviewAgent < Omakase::Agent
    instructions "You are interviewing a candidate."
    strategy :predict

    def initialize(**options)
      super
      @asked = []
    end

    def context = @asked.empty? ? nil : "Already asked:\n#{@asked.join("\n")}"

    generates :question_after, "Ask the next question."

    def ask(answer)
      @asked << question_after(answer:)
    end
  end

  def test_nothing_is_added_until_the_agent_has_something_to_remember
    chat = FakeChat.new { {"result" => "Tell me about yourself."} }
    agent = InterviewAgent.new(chat:)

    agent.ask("hello")

    refute_includes chat.instructions.first, "Already asked"
  end

  def test_an_agent_marshals_so_a_run_can_be_resumed_without_its_chat
    resumed = Marshal.load(Marshal.dump(InventoryAgent.new({"apple" => 3}, chat: FakeChat.new { {} })))

    assert_equal 3, resumed.stock_of("apple")
    refute resumed.instance_variable_defined?(:@chat)
  end

  def test_what_the_agent_kept_is_in_the_instructions_of_the_next_call
    chat = FakeChat.new { {"result" => "And after that?"} }
    agent = InterviewAgent.new(chat:)

    2.times { agent.ask("hello") }

    assert_includes chat.instructions.last, "You are interviewing a candidate."
    assert_includes chat.instructions.last, "Already asked:\nAnd after that?"
  end
end

class MemoryTest < Minitest::Test
  # A fake embedder: one dimension per word, so overlap is similarity.
  WORDS = %w[shipping refund ruby].freeze

  class SupportAgent < Omakase::Agent
    instructions "You help customers."
    memory
  end

  def setup = Omakase.embedder = ->(text) { WORDS.map { |word| text.downcase.include?(word) ? 1.0 : 0.0 } }

  def teardown = Omakase.embedder = nil

  def test_the_closest_memory_comes_back_not_the_most_recent
    agent = SupportAgent.new
    agent.remember("Shipping to Canada takes three weeks")
    agent.remember("Refunds are processed in five days")

    assert_equal ["Shipping to Canada takes three weeks"], agent.recall("why is my delivery late", limit: 1)
  end

  def test_remembering_the_same_thing_twice_is_one_memory
    agent = SupportAgent.new
    2.times { agent.remember("Refunds are processed in five days") }

    assert_equal 1, agent.recall("refund", limit: 5).size
  end

  def test_what_it_learned_survives_the_session
    agent = SupportAgent.new
    agent.remember("Shipping to Canada takes three weeks")

    resumed = Marshal.load(Marshal.dump(agent))

    assert_equal ["Shipping to Canada takes three weeks"], resumed.recall("delivery", limit: 1)
  end

  def test_both_methods_are_offered_to_the_model
    assert_equal ["recall(query, limit:) — Search what you remember, by meaning; the closest few come back",
      "remember(text) — Save something worth remembering after this run"],
      Omakase::Capabilities.of(SupportAgent)
  end
end
