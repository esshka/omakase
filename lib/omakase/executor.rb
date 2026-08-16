# frozen_string_literal: true

module Omakase
  # Runs model-written Ruby in the agent's own context.
  # ponytail: instance_eval is not a sandbox — see Executor::Subprocess.
  module Executor
    SOURCE = "(generated)"
    RESULT = :omakase_result
    OUTPUT = :omakase_output
    TIMEOUT = 30
    TRACE = /\A#{Regexp.escape(SOURCE)}:\d+/
    MAX_OUTPUT = 4_000

    # What `finish(value)` handed back: the answer as a Ruby value, not as text,
    # and whatever the code printed on the way there. `printed` defaults, so a
    # replacement executor that only knows the value still satisfies the seam.
    Answer = Data.define(:value, :printed) do
      def initialize(value:, printed: "") = super
    end

    module_function

    def call(agent, code, timeout: TIMEOUT)
      printed = StringIO.new
      answer = catch(RESULT) do
        value = capturing(printed) { Timeout.timeout(timeout) { agent.instance_eval(code, SOURCE, 1) } }
        return observation([printed.string.chomp, "=> #{value.inspect}"])
      end
      Answer.new(value: answer, printed: printed.string.chomp)
    rescue ScriptError, StandardError => e
      observation([printed.string.chomp, failure(e, code)])
    end

    # The model can only fix what it can locate, so point at the line.
    def failure(error, code)
      line = error.backtrace&.grep(TRACE)&.first&.slice(/:(\d+)/, 1)&.to_i
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

    # Generated code runs in a child process so a timeout, a crash, or a
    # runaway loop cannot take the parent with it. The child is a copy of
    # this process — it can still reach ActiveRecord, ENV, and the disk.
    # That is isolation of fate, not of capability. Untrusted input still
    # belongs to :predict.
    #
    # Ivars written in the child are marshalled back, so a generation's
    # second tool call sees what the first one set. Methods the model
    # defined on the object die with the child.
    module Subprocess
      module_function

      def call(agent, code, timeout: TIMEOUT)
        reader = writer = pid = nil
        raise Error, "Executor::Subprocess needs Process.fork" unless Process.respond_to?(:fork)

        reader, writer = IO.pipe
        reader.binmode
        writer.binmode
        pid = fork do
          reader.close
          send_packet(writer, agent, Executor.call(agent, code, timeout:))
        ensure
          exit! 0
        end
        writer.close
        take_packet(reader, agent, pid, timeout)
      ensure
        reader.close if reader && !reader.closed?
        reap(pid)
      end

      def send_packet(io, agent, result)
        io.write(dump(agent, result))
      ensure
        io.close
      end

      def dump(agent, result)
        Marshal.dump({result:, state: agent.marshal_dump})
      rescue TypeError
        Marshal.dump({result: carry(result), state: nil})
      end

      def carry(result)
        Marshal.dump(result)
        result
      rescue TypeError => e
        klass = result.is_a?(Answer) ? result.value.class : result.class
        Executor.observation(["cannot return #{klass} across the process boundary: #{e.message}"])
      end

      def take_packet(reader, agent, pid, timeout)
        ready, = IO.select([reader], nil, nil, timeout)
        return timed_out(pid) unless ready

        payload = reader.read
        return child_ended(pid) if payload.nil? || payload.empty?

        packet = Marshal.load(payload)
        agent.marshal_load(packet[:state]) if packet[:state]
        packet[:result]
      rescue TypeError, ArgumentError
        child_ended(pid)
      end

      def timed_out(pid)
        stop(pid)
        Executor.observation(["execution timed out"])
      end

      def child_ended(pid)
        Executor.observation(["child process #{fate(reap(pid))}"])
      end

      def fate(status)
        return "was killed" if status.nil? || status.signaled?
        return "ended without an answer" if status.success?

        "exited #{status.exitstatus}"
      end

      def stop(pid)
        Process.kill("KILL", pid)
      rescue Errno::ESRCH, TypeError
        nil
      end

      def reap(pid)
        Process.wait2(pid)&.last if pid
      rescue Errno::ECHILD
        nil
      end
    end
  end
end
