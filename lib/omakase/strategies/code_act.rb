# frozen_string_literal: true

module Omakase
  module Strategies
    # The model acts by writing Ruby against the agent object and answers with
    # `finish(value)` — the answer is computed, not retyped.
    module CodeAct
      module_function

      def call(request)
        tool = Tools::Ruby.new(request.agent, request.schema)
        notes = request.chat
          .with_instructions(instructions(request))
          .with_tool(tool)
          .ask(request.task)
          .content

        return tool.answer.value if tool.answer

        # It never called finish: fall back to a tool-free turn under the schema.
        Predict.call(request, task: "#{request.task}\n\nWork done:\n#{notes}")
      end

      def instructions(request)
        <<~TEXT
          #{request.instructions}

          You act by writing Ruby: call the `ruby` tool with code that is evaluated on the
          agent object, so its methods and state are available on self.

          #{capabilities(request).join("\n")}

          `doc(object)` prints what an object of an unfamiliar type offers.

          Return the answer from inside the code, never as a message — the last thing you run is:

              finish(#{request.schema.describe})

          Work in as few tool calls as you can.
        TEXT
      end

      def capabilities(request)
        Capabilities.of(request.agent.class, except: request.generation.name).map { |entry| "- #{entry}" }
      end
    end
  end
end
