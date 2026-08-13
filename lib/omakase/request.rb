# frozen_string_literal: true

module Omakase
  # One invocation of a generation method: all a strategy may depend on.
  Request = Data.define(:agent, :generation, :inputs) do
    def chat = agent.chat

    def schema = generation.schema

    def instructions = [agent.class.instructions, agent.context].reject { |text| text.to_s.empty? }.join("\n\n")

    def task
      return prompt if inputs.empty?

      arguments = inputs.map { |name, value| "- #{name}: #{value.inspect}" }
      "#{prompt}\n\nInputs:\n#{arguments.join("\n")}"
    end

    # A prompt written as a block is read at call time, on the agent — so one
    # declaration serves an object however it happens to be configured.
    def prompt
      text = generation.prompt
      text.is_a?(Proc) ? agent.instance_exec(&text) : text
    end
  end
end
