# frozen_string_literal: true

module Omakase
  module Tools
    # The model's one tool. Every capability of the agent reaches the model
    # through it, so the model composes calls in code instead of one per turn.
    class Ruby < RubyLLM::Tool
      BUDGET = 10

      description <<~TEXT
        Evaluate Ruby in the context of the agent object: its methods and state are
        directly available on self. Anything printed, plus the value of the last
        expression, is returned to you. Call finish(value) to answer.
      TEXT

      param :code, desc: "Ruby source to evaluate."

      attr_reader :answer

      def initialize(agent, schema, budget: BUDGET)
        super()
        @agent = agent
        @schema = schema
        @budget = budget
        @calls = 0
      end

      def name = "ruby"

      def execute(code:)
        # Nothing bounds the provider's tool loop, so the budget does.
        @calls += 1
        return "No tool calls left — answer with what you have." if @calls == @budget + 1
        return halt("Tool budget spent.") if @calls > @budget + 1

        outcome = Executor.call(@agent, code)
        return outcome unless outcome.is_a?(Executor::Answer)

        @answer = Executor::Answer.new(value: @schema.take(outcome.value))
        halt("Answer accepted.")
      rescue Error => e
        # Off-contract answers are corrected inside the same loop, not by another request.
        "finish rejected: #{e.message}"
      end
    end
  end
end
