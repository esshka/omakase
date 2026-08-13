# frozen_string_literal: true

module Omakase
  # One invocation of a generation method: all a strategy may depend on.
  Request = Data.define(:agent, :generation, :inputs) do
    def chat = agent.chat

    def schema = generation.schema

    def instructions = [agent.class.instructions, agent.context].reject { |text| text.to_s.empty? }.join("\n\n")

    def task
      return generation.prompt if inputs.empty?

      arguments = inputs.map { |name, value| "- #{name}: #{value.inspect}" }
      "#{generation.prompt}\n\nInputs:\n#{arguments.join("\n")}"
    end
  end
end
