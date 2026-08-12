# frozen_string_literal: true

module Omakase
  # Runs model-written Ruby in the agent's own context.
  # ponytail: instance_eval is not a sandbox — see Omakase.executor to swap it.
  module Executor
    SOURCE = "(generated)"
    RESULT = :omakase_result
    OUTPUT = :omakase_output
    TIMEOUT = 30
    MAX_OUTPUT = 4_000

    # What `finish(value)` handed back: the answer as a Ruby value, not as text.
    Answer = Data.define(:value)

    module_function

    def call(agent, code, timeout: TIMEOUT)
      printed = StringIO.new
      answer = catch(RESULT) do
        value = capturing(printed) { Timeout.timeout(timeout) { agent.instance_eval(code, SOURCE, 1) } }
        return observation([printed.string.chomp, "=> #{value.inspect}"])
      end
      Answer.new(value: answer)
    rescue ScriptError, StandardError => e
      observation([printed.string.chomp, failure(e, code)])
    end

    # The model can only fix what it can locate, so point at the line.
    def failure(error, code)
      line = error.backtrace&.grep(/\A#{Regexp.escape(SOURCE)}:\d+/)&.first&.slice(/:(\d+)/, 1)&.to_i
      source = code.lines[line - 1]&.strip if line&.positive?
      ["#{error.class}: #{error.message}", ("line #{line}: #{source}" if source)].compact.join("\n")
    end

    def observation(parts)
      text = parts.reject(&:empty?).join("\n")
      text = "#{text[0, MAX_OUTPUT]}\n… (truncated)" if text.length > MAX_OUTPUT
      text.empty? ? "(no output)" : text
    end

    # Thread-local, so concurrent agents never share a buffer. Agent#puts reads it.
    def capturing(io)
      previous = Thread.current[OUTPUT]
      Thread.current[OUTPUT] = io
      yield
    ensure
      Thread.current[OUTPUT] = previous
    end
  end
end
