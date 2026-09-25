# frozen_string_literal: true

module Omakase
  module Strategies
    # One call, no code execution: the model answers straight into the schema.
    module Predict
      CORRECTION = "Answer again as JSON, and nothing else."

      module_function

      def call(request, task: request.task)
        chat = instruct(request.chat, instructions(request), request.context)
          .with_schema(request.schema.definition)

        request.schema.cast(chat.ask(task, with: request.attachments).content)
      rescue ContractError => e
        # One correction turn, told exactly what was wrong with the last answer.
        request.schema.cast(chat.ask("#{e.message}\n\n#{CORRECTION}").content)
      end

      # The stable text first and marked for the cache; the context, which
      # changes from call to call, after it.
      def instruct(chat, stable, context)
        chat = chat.with_instructions(stable, cache_until_here: true)
        context.empty? ? chat : chat.with_instructions(context, append: true)
      end

      # Weaker providers treat the schema as a hint, so it goes in the prompt too.
      def instructions(request)
        "#{request.instructions}\n\nAnswer as JSON matching this schema:\n#{JSON.generate(request.schema.json)}"
      end
    end
  end
end
