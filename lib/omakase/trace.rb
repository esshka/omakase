# frozen_string_literal: true

module Omakase
  # The listener, printed for a human: `Omakase.listener = Omakase::Trace.new`.
  # A run reads top to bottom — the call, the code the model wrote, the answer.
  # Colour when the stream is a terminal, plain when it is a log.
  class Trace
    COLOURS = {generation: 36, ruby: 33, answer: 32, error: 31, mcp: 31}.freeze
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
      when :error then ["✗ #{agent.class}##{payload[:name]}", truncate("#{payload[:error].class}: #{payload[:error].message}")]
      # A down sidecar is not an error the run raises, so nothing else would say it.
      when :mcp then ["! #{agent} mcp #{payload[:name]}", truncate(payload[:error].message)]
      else return # a listener that raises takes the run down with it
      end

      # A generation called from generated code sits inside its caller's.
      indent = "    " * [(Thread.current[Agent::RUNNING]&.size || 1) - 1, 0].max
      @io.puts(indent + paint(event, head))
      @io.puts(body.gsub(/^/, "#{indent}    ")) unless body.empty?
    end

    private

    def inputs(inputs) = inputs.map { |name, value| "#{name}: #{truncate(value.inspect)}" }.join("\n")

    # An Answer is `finish(value)` ending the run — with anything printed before it,
    # which the tool result never carries because the run is over. Otherwise the
    # outcome is already the text the model reads.
    def outcome(outcome)
      return truncate(outcome.to_s) unless outcome.is_a?(Executor::Answer)

      truncate([outcome.printed, "finish #{outcome.value.inspect}"].reject(&:empty?).join("\n"))
    end

    def truncate(text) = (text.length > LIMIT) ? "#{text[0, LIMIT]}…" : text

    def paint(event, text) = @colour ? "\e[#{COLOURS.fetch(event)}m#{text}\e[0m" : text
  end
end
