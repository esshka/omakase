# frozen_string_literal: true

# ruby examples/interview_agent.rb
require_relative "setup"

# The chat is fresh every call, so what the agent remembers is what it keeps.
# `context` renders that state into the instructions of the next call.
class InterviewAgent < ApplicationAgent
  instructions "You interview a Ruby candidate. One question at a time, no preamble."
  strategy :predict

  def initialize(**options)
    super
    @asked = []
  end

  def context = @asked.empty? ? nil : "Questions you already asked:\n- #{@asked.join("\n- ")}"

  generates :question_after, "Ask the next question, on a topic you have not covered yet."

  def ask(answer)
    @asked << question_after(answer:)
    @asked.last
  end
end

agent = InterviewAgent.new
answer = "I have three years of Ruby, mostly Rails APIs."

3.times do
  question = agent.ask(answer)
  puts question
  answer = "I would look at it, but I have not had to do that in production."
end
