# frozen_string_literal: true

module Omakase
  module Tools
    # The model's one tool. Every capability of the agent reaches the model
    # through it, so the model composes calls in code instead of one per turn.
    class Ruby < RubyLLM::Tool
      description <<~TEXT
        Evaluate Ruby in the context of the agent object: its methods and state are
        directly available on self. Anything printed, plus the value of the last
        expression, is returned to you.
      TEXT

      param :code, desc: "Ruby source to evaluate."

      def initialize(agent)
        super()
        @agent = agent
      end

      def name = "ruby"

      def execute(code:) = Executor.call(@agent, code)
    end
  end
end
