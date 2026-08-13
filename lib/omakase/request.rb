# frozen_string_literal: true

module Omakase
  # One invocation of a generation method: all a strategy may depend on.
  Request = Data.define(:agent, :generation, :inputs) do
    def chat = agent.chat(**{model: generation.model}.compact)

    def schema = generation.schema

    def instructions = [agent.class.instructions, agent.context].reject { |text| text.to_s.empty? }.join("\n\n")

    # `with:` is reserved: files for the model to look at, passed through to
    # RubyLLM's `ask(with:)` as attachments rather than rendered into the text.
    def attachments = inputs[:with]

    def task
      arguments = inputs.except(:with)
      return prompt if arguments.empty?

      lines = arguments.map { |name, value| "- #{name}: #{value.inspect}" }
      "#{prompt}\n\nInputs:\n#{lines.join("\n")}"
    end

    # A prompt written as a block is read at call time, on the agent — so one
    # declaration serves an object however it happens to be configured.
    def prompt
      text = generation.prompt
      text.is_a?(Proc) ? agent.instance_exec(&text) : text
    end
  end
end
