# frozen_string_literal: true

module Omakase
  module Tools
    # The model's one tool. Every capability of the agent reaches the model
    # through it, so the model composes calls in code instead of one per turn.
    class Ruby < RubyLLM::Tool
      description <<~TEXT
        Evaluate Ruby in the context of the agent object: its methods and state are
        directly available on self. Anything printed, plus the value of the last
        expression, is returned to you. Call finish(value) to answer.
      TEXT

      param :code, desc: "Ruby source to evaluate."

      attr_reader :answer

      def initialize(agent, schema)
        super()
        @agent = agent
        @schema = schema
      end

      def name = "ruby"

      def execute(code:)
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
