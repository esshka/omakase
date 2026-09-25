# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/omakase"

class HardeningTest < Minitest::Test
  class ShopAgent < Omakase::Agent
    instructions "You run a shop."

    describe "Price of an item, in cents"
    def price_of(item) = {"mug" => 900, "pen" => 150}.fetch(item, 0)

    generates :total, "Total price of the items.", takes: %i[items], returns: :integer

    generates :report do
      array :tags, of: :string
      object :meta do
        integer :count
      end
    end
  end

  def agent(*replies) = ShopAgent.new(chat: Omakase::FakeChat.replies(*replies))

  def test_exit_in_generated_code_does_not_end_the_host
    observation = Omakase::Executor.call(ShopAgent.new, "puts 'before'; exit 3")

    assert_equal "before\nexit is not allowed — answer with finish(value)", observation
  end

  def test_the_error_survives_output_past_the_cap
    observation = Omakase::Executor.call(ShopAgent.new, "puts 'x' * 10_000; raise 'the real bug'")

    assert_includes observation, "characters truncated"
    assert_includes observation, "RuntimeError: the real bug"
  end

  def test_finish_is_held_to_the_nested_schema
    tool = Omakase::Tools::Ruby.new(ShopAgent.new, ShopAgent.generations[:report].schema)

    assert_match(/tags\[0\]: expected <string>, got 1/, tool.execute(code: "finish(tags: [1], meta: {count: 1})"))
    assert_match(/meta\.count: expected <integer>/, tool.execute(code: %(finish(tags: [], meta: {count: "1"}))))
    assert_equal "Answer accepted.", tool.execute(code: "finish(tags: ['a'], meta: {count: 1})")
  end

  def test_the_inputs_are_locals_in_the_generated_code
    chat = Omakase::FakeChat.replies(->(fake) { fake.run("finish(items.sum { |item| price_of(item) })") })

    assert_equal 1050, ShopAgent.new(chat:).total(items: %w[mug pen])
  end

  def test_locals_last_for_the_rest_of_the_generation
    chat = Omakase::FakeChat.replies(->(fake) {
      fake.run("prices = items.map { |item| price_of(item) }")
      fake.run("finish(prices.max)")
    })

    assert_equal 900, ShopAgent.new(chat:).total(items: %w[mug pen])
  end

  def test_a_large_input_is_only_previewed_in_the_prompt
    chat = Omakase::FakeChat.replies(->(fake) { fake.run("finish(items.size)") })

    assert_equal 1000, ShopAgent.new(chat:).total(items: ["mug"] * 1000)
    assert_includes chat.tasks.first, "the whole value is in the local"
    assert_operator chat.tasks.first.length, :<, 1_000
  end

  def test_a_text_reply_is_nudged_before_any_fallback
    chat = Omakase::FakeChat.replies("I think it is 1050.", ->(fake) { fake.run("finish(1050)") })

    assert_equal 1050, ShopAgent.new(chat:).total(items: %w[mug pen])
    assert_includes chat.tasks.last, "no tool call"
    assert_includes chat.tasks.last, "finish(<integer>)"
  end

  def test_generations_cannot_nest_past_the_limit
    Thread.current[Omakase::Agent::RUNNING] = Array.new(Omakase::Agent::MAX_DEPTH) { |i| {key: [i, :outer], inputs: {}} }

    error = assert_raises(Omakase::Error) { agent.total(items: []) }
    assert_match(/nest deeper than 10/, error.message)
  ensure
    Thread.current[Omakase::Agent::RUNNING] = nil
  end

  def test_the_stable_prompt_comes_first_and_is_marked_for_the_cache
    RubyLLM.config.openai_api_key = "unused"
    chat = Omakase.build_chat(model: "gpt-5", provider: :openai, assume_model_exists: true)

    Omakase::Strategies::Predict.instruct(chat, "stable", "changes")

    assert_equal [["stable", true], ["changes", false]], chat.messages.map { [_1.content, _1.cache_until_here?] }
  ensure
    RubyLLM.config.openai_api_key = nil
  end

  def test_chat_options_become_the_chats_own_settings
    RubyLLM.config.openai_api_key = "unused"
    options = {model: "gpt-5", provider: :openai, assume_model_exists: true}

    chat = Omakase.build_chat(**options, temperature: 0.2, thinking: {effort: :high})
    assert_equal 0.2, chat.instance_variable_get(:@temperature)
    assert_equal({effort: :high}, chat.thinking)
    assert_equal({}, chat.instance_variable_get(:@caching))
    refute Omakase.build_chat(**options, caching: false).instance_variable_get(:@caching)

    error = assert_raises(Omakase::Error) { Omakase.build_chat(**options, colour: :blue) }
    assert_match(/no #with_colour/, error.message)
  ensure
    RubyLLM.config.openai_api_key = nil
  end

  def test_a_fenced_block_of_code_runs_as_code
    tool = Omakase::Tools::Ruby.new(ShopAgent.new, Omakase::Schema.define(returns: :integer))

    assert_equal "=> 900", tool.execute(code: "```ruby\nprice_of('mug')\n```")
    assert_equal %(=> "```"), tool.execute(code: %("```"))
  end

  def test_scripted_replies_run_out_loudly
    error = assert_raises(Omakase::Error) { agent("prose").total(items: []) }

    assert_match(/no scripted reply left/, error.message)
  end

  def test_the_trace_shows_a_failed_generation_and_nests_inner_ones
    io = StringIO.new
    Omakase.listener = Omakase::Trace.new(io:)
    inner = ShopAgent.new(chat: Omakase::FakeChat.replies(->(fake) { fake.run("finish(1)") }))
    outer = ShopAgent.new(chat: Omakase::FakeChat.replies(->(fake) { fake.run("finish(@inner.total(items: []))") }))
    outer.instance_variable_set(:@inner, inner)

    outer.total(items: [])
    assert_includes io.string, "\n    → HardeningTest::ShopAgent#total"

    assert_raises(Omakase::Error) { agent.total(items: []) }
    assert_includes io.string, "✗ HardeningTest::ShopAgent#total"
  ensure
    Omakase.listener = nil
  end

  def test_skill_front_matter_that_is_not_yaml_still_reads
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "SKILL.md"), "---\r\nname: grind\r\ndescription: Grinds café beans\r\nargument-hint: \"<beans>\" [-f]\r\n---\r\nGrind them.\r\n")
      agent_class = Class.new(Omakase::Agent) { skill dir }

      assert_includes Omakase::Capabilities.of(agent_class), "grind() — Grinds café beans"
      assert_match(/\AGrind them\./, agent_class.new.grind)
    end
  end
end
