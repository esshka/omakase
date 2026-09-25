# frozen_string_literal: true

module Omakase
  # Runs model-written Ruby in the agent's own context.
  # ponytail: instance_eval is not a sandbox — Subprocess isolates a crash, not File.
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
        value = capturing(printed) { Timeout.timeout(timeout) { evaluate(agent, code) } }
        return observation([printed.string.chomp, "=> #{value.inspect}"])
      end
      Answer.new(value: answer, printed: printed.string.chomp)
    rescue ScriptError, StandardError => e
      observation([printed.string.chomp, failure(e, code)])
    rescue SystemExit
      # In process, exit would end the host. exit! cannot be caught: Subprocess covers that.
      observation([printed.string.chomp, "exit is not allowed — answer with finish(value)"])
    end

    # Inside a generation the inputs are locals; outside one, plain instance_eval.
    def evaluate(agent, code)
      scope = agent.respond_to?(:omakase_scope, true) && agent.send(:omakase_scope)
      scope ? scope.eval(code, SOURCE, 1) : agent.instance_eval(code, SOURCE, 1)
    end

    # The model can only fix what it can locate, so point at the line. A
    # SyntaxError has no generated frame to point from.
    def failure(error, code)
      message = "#{error.class}: #{error.message}"
      line = error.backtrace.grep(TRACE).first&.slice(/:(\d+)/, 1)&.to_i
      return message unless line

      "#{message}\nline #{line}: #{code.lines[line - 1].to_s.strip}"
    end

    # Head and tail: the error or the value comes last, and it is what the model needs next.
    def observation(parts)
      text = parts.reject(&:empty?).join("\n")
      return text if text.length <= MAX_OUTPUT

      half = MAX_OUTPUT / 2
      "#{text[0, half]}\n… (#{text.length - MAX_OUTPUT} characters truncated)\n#{text[-half..]}"
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
    # Ivars written in the child are marshalled back one at a time, so a
    # generation's second tool call sees what the first one set. Methods
    # the model defined on the object die with the child.
    module Subprocess
      module_function

      def call(agent, code, timeout: TIMEOUT)
        IO.pipe(binmode: true) do |reader, writer|
          pid = fork do
            reader.close
            # Own process group, so a timeout can kill grandchildren too.
            Process.setsid
            # Parent owns the deadline; Timeout here would race it.
            payload = pack(agent, Executor.call(agent, code, timeout: nil))
            writer.write([payload.bytesize].pack("N"), payload)
          ensure
            exit! 0
          end
          writer.close
          collect(reader, agent, pid, clock + timeout)
        end
      end

      def collect(reader, agent, pid, deadline)
        payload = read_packet(reader, deadline)
        stop(pid) if payload == :timeout
        status = reap(pid)
        case payload
        when :timeout then "execution timed out"
        when :eof then "child process #{fate(status)}"
        else unpack(agent, payload)
        end
      end

      def pack(agent, result)
        kept, dropped = agent.marshal_dump.partition { |_, value| marshalable?(value) }
        result = note_dropped(result, dropped.map(&:first))
        Marshal.dump({result: carry(result), state: kept.to_h})
      end

      def marshalable?(value)
        Marshal.dump(value)
        true
      rescue TypeError
        false
      end

      # A dropped ivar turns the answer into an observation: silent state loss
      # would leave the next tool call reasoning about a value that is gone.
      def note_dropped(result, dropped)
        return result if dropped.empty?

        prior = result.is_a?(Answer) ? [result.printed, "finish #{result.value.inspect}"].reject(&:empty?).join("\n") : result
        Executor.observation([prior, "cannot keep #{dropped.join(", ")} across the process boundary"])
      end

      # Only an Answer can fail here — an observation is a String.
      def carry(result)
        return result if marshalable?(result)

        "cannot return #{result.value.class} across the process boundary"
      end

      def unpack(agent, payload)
        packet = Marshal.load(payload)
        agent.marshal_load(packet[:state])
        packet[:result]
      rescue ArgumentError, TypeError => e
        "#{e.message}: a class defined in generated code does not survive the process boundary"
      end

      # Length-prefixed, so a leftover write-end cannot hang the parent.
      def read_packet(io, deadline)
        header = read_exactly(io, 4, deadline)
        return header if header.is_a?(Symbol)

        read_exactly(io, header.unpack1("N"), deadline)
      end

      # select is exact for a pipe, so readpartial cannot block past the deadline.
      def read_exactly(io, n, deadline)
        buf = "".b
        while buf.bytesize < n
          return :timeout unless IO.select([io], nil, nil, [deadline - clock, 0].max)

          buf << io.readpartial(n - buf.bytesize)
        end
        buf
      rescue EOFError
        :eof
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def fate(status)
        return "was killed" if status.nil? || status.signaled?
        return "ended without an answer" if status.success?

        "exited #{status.exitstatus}"
      end

      # The child led its own group unless the deadline beat it to setsid.
      def stop(pid)
        Process.kill("KILL", (Process.getpgid(pid) == pid) ? -pid : pid)
      rescue Errno::ESRCH
        nil
      end

      # ECHILD: the host reaps children itself, with a CHLD trap.
      def reap(pid)
        Process.wait2(pid).last
      rescue Errno::ECHILD
        nil
      end
    end
  end
end
