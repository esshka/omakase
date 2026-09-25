# frozen_string_literal: true

module Omakase
  # One invocation of a generation method: all a strategy may depend on.
  Request = Data.define(:agent, :generation, :inputs) do
    def chat = agent.chat(**{model: generation.model}.compact)

    def schema = generation.schema

    def instructions = agent.class.instructions

    # Rebuilt on every call, so it goes after what a provider can cache.
    def context = agent.context.to_s

    # `with:` is reserved: files for the model to look at, passed through to
    # RubyLLM's `ask(with:)` as attachments rather than rendered into the text.
    def attachments = inputs[:with]

    # With `preview:`, the model's code holds the inputs, so the prompt only shows them.
    def task(preview: false)
      arguments = inputs.except(:with)
      return prompt if arguments.empty?

      lines = arguments.map { |name, value| "- #{name}: #{preview ? shorten(value.inspect) : value.inspect}" }
      "#{prompt}\n\nInputs:\n#{lines.join("\n")}"
    end

    # A prompt written as a block is read at call time, on the agent — so one
    # declaration serves an object however it happens to be configured.
    def prompt
      text = generation.prompt
      text.is_a?(Proc) ? agent.instance_exec(&text) : text
    end

    # Past the limit, code_act shows the start of an input: the whole value is a local.
    # ponytail: inspects the whole value, then cuts; a bounded printer if a huge input shows up in a profile.
    def shorten(text, limit = 500)
      return text if text.length <= limit

      "#{text[0, limit]}… (#{text.length} characters — the whole value is in the local)"
    end
  end
end
