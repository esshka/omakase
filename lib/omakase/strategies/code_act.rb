# frozen_string_literal: true

module Omakase
  module Strategies
    # The model acts by writing Ruby against the agent object until it can
    # answer, then answers in the declared shape.
    module CodeAct
      module_function

      def call(request)
        notes = request.chat
          .with_instructions(instructions(request))
          .with_tool(Tools::Ruby.new(request.agent))
          .ask(request.task)
          .content

        # Tools and structured output in one request make providers fall back to
        # prose, so the answer is a second, tool-free turn.
        Predict.call(request, task: "#{request.task}\n\nWork done:\n#{notes}")
      end

      def instructions(request)
        <<~TEXT
          #{request.instructions}

          You act by writing Ruby: call the `ruby` tool with code that is evaluated on the
          agent object, so its methods and state are available on self.

          #{capabilities(request).join("\n")}

          `doc(object)` prints what an object of an unfamiliar type offers.
          Work in as few calls as you can, then answer.
        TEXT
      end

      def capabilities(request)
        Capabilities.of(request.agent.class, except: request.generation.name).map { |entry| "- #{entry}" }
      end
    end
  end
end
