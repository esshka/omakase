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
  #
  # Or one reply per model turn, in order; a turn past the last one raises:
  #
  #   Omakase::FakeChat.replies("prose, not JSON", {"result" => 42})
  class FakeChat
    Response = Struct.new(:content)

    def self.replies(*replies)
      new do |chat|
        raise Error, "FakeChat: no scripted reply left for turn #{chat.tasks.size}" if replies.empty?

        reply = replies.shift
        reply.respond_to?(:call) ? reply.call(chat) : reply
      end
    end

    attr_reader :instructions, :schema, :tools, :tasks, :attachments

    def initialize(&script)
      @script = script
      @instructions = []
      @tools = []
      @tasks = []
      @attachments = []
      @complete = true
    end

    # A log of every call — the real chat replaces unless `append:`.
    def with_instructions(text, **) = tap { @instructions << text }

    def with_schema(schema) = tap { @schema = schema }

    def with_tools(*tools) = tap { @tools.concat(tools) }

    def ask(task, with: nil) = ask_later(task, with:).step

    def ask_later(task, with: nil)
      @tasks << task
      @attachments << with if with
      tap { @complete = false }
    end

    # The whole script is one step: it answers, so the chat is then complete.
    def step
      @complete = true
      Response.new(@script.call(self))
    end

    def complete? = @complete

    # Run code the way the model would, through the agent's one tool.
    def run(code) = tools.fetch(0).call(code:)
  end
end
