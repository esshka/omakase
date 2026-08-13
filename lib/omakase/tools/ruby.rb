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

      def initialize(agent, schema, budget: BUDGET, timeout: Executor::TIMEOUT, executor: Omakase.executor)
        super()
        @agent = agent
        @schema = schema
        @budget = budget
        @timeout = timeout
        @executor = executor
        @calls = 0
      end

      def name = "ruby"

      def execute(code:)
        # Nothing bounds the provider's tool loop, so the budget does.
        @calls += 1
        return "No tool calls left — answer with what you have." if @calls == @budget + 1
        return halt("Tool budget spent.") if @calls > @budget + 1

        outcome = @executor.call(@agent, code, timeout: @timeout)
        Omakase.emit(:ruby, agent: @agent, code:, outcome:)
        return outcome if outcome.is_a?(String)
        # The seam's contract, checked here so a wrong executor cannot reach the model.
        raise Error, "executor must return a String or Executor::Answer, got #{outcome.class}" unless outcome.is_a?(Executor::Answer)

        @answer = Executor::Answer.new(value: @schema.take(outcome.value))
        halt("Answer accepted.")
      rescue ContractError => e
        # Off-contract answers are corrected inside the same loop, not by another request.
        # Anything else — a broken executor, a bad configuration — is not the model's to fix.
        "finish rejected: #{e.message}"
      end
    end
  end
end
