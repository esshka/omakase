# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/omakase"

# Plays the provider: records how each chat was configured and runs the script,
# which may drive the tools before returning the content.
class FakeChat
  Response = Struct.new(:content)

  attr_reader :instructions, :schema, :tools, :tasks

  def initialize(&script)
    @script = script
    @instructions = []
    @tools = []
    @tasks = []
  end

  def with_instructions(text) = tap { @instructions << text }

  def with_schema(schema) = tap { @schema = schema }

  def with_tool(tool, **) = tap { @tools << tool }

  def ask(task)
    @tasks << task
    Response.new(@script.call(self))
  end

  # What the model would do with its one tool.
  def run(code) = tools.fetch(0).call(code:)
end

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
  # The model works with the tool, then answers in a tool-free second turn.
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

  def test_instructions_list_the_agents_methods_but_not_the_one_being_written
    chat = FakeChat.new { |fake| fake.schema ? {"result" => 0} : "done" }
    InventoryAgent.new({}, chat:).total_stock(items: [])

    assert_includes chat.instructions.first, "You check inventory."
    assert_includes chat.instructions.first, "- stock_of(item) — Units of an item on hand"
    refute_includes chat.instructions.first, "total_stock"
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

  def test_only_scalars_are_accepted_as_shorthand_return_types
    error = assert_raises(Omakase::Error) { Omakase::Schema.define(returns: :order) }
    assert_match(/returns: must be one of/, error.message)
  end
end
