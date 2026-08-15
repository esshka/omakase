# frozen_string_literal: true

module Omakase
  # The listener, printed for a human: `Omakase.listener = Omakase::Trace.new`.
  # A run reads top to bottom — the call, the code the model wrote, the answer.
  # Colour when the stream is a terminal, plain when it is a log.
  class Trace
    COLOURS = {generation: 36, ruby: 33, answer: 32}.freeze
    LIMIT = 800

    def initialize(io: $stderr)
      @io = io
      @colour = io.respond_to?(:tty?) && io.tty?
    end

    def call(event, agent:, **payload)
      head, body = case event
      when :generation then ["→ #{agent.class}##{payload[:name]}", inputs(payload[:inputs])]
      when :ruby then ["· ruby", "#{payload[:code].strip}\n#{outcome(payload[:outcome])}"]
      when :answer then ["← #{agent.class}##{payload[:name]}", truncate(payload[:value].inspect)]
      else return # a listener that raises takes the run down with it
      end

      @io.puts(paint(event, head))
      @io.puts(body.gsub(/^/, "    ")) unless body.empty?
    end

    private

    def inputs(inputs) = inputs.map { |name, value| "#{name}: #{truncate(value.inspect)}" }.join("\n")

    # An Answer is `finish(value)` ending the run; anything else is what the code printed.
    def outcome(outcome)
      truncate(outcome.is_a?(Executor::Answer) ? "finish #{outcome.value.inspect}" : outcome.to_s)
    end

    def truncate(text) = (text.length > LIMIT) ? "#{text[0, LIMIT]}…" : text

    def paint(event, text) = @colour ? "\e[#{COLOURS.fetch(event)}m#{text}\e[0m" : text
  end
end
