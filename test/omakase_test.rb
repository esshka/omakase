# frozen_string_literal: true

require "minitest/autorun"
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

class TicketAgent < Omakase::Agent
  instructions "You file tickets."

  generates :file, "File a ticket for the message.", returns: Ticket
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

  def test_a_ruby_class_return_type_hands_back_the_object_itself
    chat = FakeChat.new do |fake|
      fake.run(%(finish(Ticket.new("A-1", "high"))))
      "done"
    end

    ticket = TicketAgent.new(chat:).file(message: "it arrived cracked")

    assert_instance_of Ticket, ticket
    assert_equal "A-1", ticket.id
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

  def test_generated_code_cannot_run_forever
    observation = Omakase::Executor.call(@agent, "sleep 5", timeout: 0.05)

    assert_match(/Timeout::Error/, observation)
  end

  def test_the_executor_is_swappable
    stub = Object.new
    def stub.call(_agent, code, timeout:) = Omakase::Executor::Answer.new(value: code.length)
    tool = Omakase::Tools::Ruby.new(@agent, Omakase::Schema.define(returns: :integer), executor: stub)

    tool.execute(code: "abc")

    assert_equal 3, tool.answer.value
  end

  def test_provider_failures_arrive_as_one_error_type
    chat = FakeChat.new { raise RubyLLM::RateLimitError.new(nil, "slow down") }

    error = assert_raises(Omakase::ProviderError) { FeedbackAgent.new(chat:).sentiment_of(text: "x") }
    assert_match(/FeedbackAgent#sentiment_of/, error.message)
  end
end

class DslTest < Minitest::Test
  def test_the_method_name_is_the_prompt_when_none_is_given
    assert_equal "Analyze.", FeedbackAgent.generations[:analyze].prompt
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
