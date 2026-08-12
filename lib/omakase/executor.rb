# frozen_string_literal: true

module Omakase
  # Runs model-written Ruby in the agent's own context.
  # ponytail: instance_eval is not a sandbox — run such agents in a container.
  module Executor
    SOURCE = "(generated)"
    RESULT = :omakase_result
    MAX_OUTPUT = 4_000

    # What `finish(value)` handed back: the answer as a Ruby value, not as text.
    Answer = Data.define(:value)

    module_function

    def call(agent, code)
      printed = StringIO.new
      answer = catch(RESULT) do
        value = capturing(printed) { agent.instance_eval(code, SOURCE, 1) }
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

    # ponytail: global $stdout swap — fine single-threaded.
    def capturing(io)
      previous = $stdout
      $stdout = io
      yield
    ensure
      $stdout = previous
    end
  end
end
