# frozen_string_literal: true

module Omakase
  # Stands in for a RubyLLM::Chat so agents can be tested without a network:
  # records how the chat was configured, then runs the script you gave it.
  #
  #   agent = SupportAgent.new(chat: Omakase::FakeChat.new { {"severity" => "high"} })
  #
  # The script receives the chat, so it can drive the tool the way a model would:
  #
  #   Omakase::FakeChat.new { |chat| chat.run("finish(42)") }
  class FakeChat
    Response = Struct.new(:content)

    attr_reader :instructions, :schema, :tools, :tasks, :attachments

    def initialize(&script)
      @script = script
      @instructions = []
      @tools = []
      @tasks = []
      @attachments = []
    end

    def with_instructions(text) = tap { @instructions << text }

    def with_schema(schema) = tap { @schema = schema }

    def with_tool(tool, **) = tap { @tools << tool }

    def ask(task, with: nil)
      @tasks << task
      @attachments << with if with
      Response.new(@script.call(self))
    end

    # Run code the way the model would, through the agent's one tool.
    def run(code) = tools.fetch(0).call(code:)
  end
end
