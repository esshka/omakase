# frozen_string_literal: true

module Omakase
  module Strategies
    # The model acts by writing Ruby against the agent object and answers with
    # `finish(value)` — the answer is computed, not retyped.
    module CodeAct
      module_function

      def call(request)
        tool = Tools::Ruby.new(request.agent, request.schema)
        chat = Predict.instruct(request.chat, instructions(request), request.context)
          .with_tools(tool)
          .ask_later(request.task(preview: true), with: request.attachments)
        response = run(chat, tool)
        # A text reply is usually a model that forgot how to answer, not one that is done.
        response = run(chat.ask_later(nudge(request)), tool) unless tool.done?
        return tool.answer.value if tool.answer

        notes = response&.content

        # It never called finish. A JSON answer can still be given in a tool-free turn.
        return Predict.call(request, task: "#{request.task}\n\nWork done:\n#{notes}") unless request.schema.code_only?

        # An object cannot come back as JSON, so there is nowhere to fall back to.
        raise ContractError, "#{request.generation.name}: the model never called finish(#{request.schema.describe})"
      end

      def run(chat, tool)
        response = nil
        response = chat.step until chat.complete? || tool.done?
        response
      end

      def nudge(request)
        "Your reply was text with no tool call, so the task is not done. " \
          "Call the `ruby` tool and end with finish(#{request.schema.describe})."
      end

      # Nothing here changes between calls of one generation, so providers can cache it.
      def instructions(request)
        <<~TEXT
          #{request.instructions}

          You act by writing Ruby: call the `ruby` tool with code that is evaluated on the
          agent object, so its methods and state are available on self. The inputs are
          local variables in that code — use them, do not retype them.

          #{capabilities(request).join("\n")}

          `doc(object)` prints what an object of an unfamiliar type offers; a class works too.
          `how_to_act` is the rest, with examples — call it once before you write code.

          Run the task; do not define a method for it. Return the answer from inside the
          code, never as a message — the last thing you run is:

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
