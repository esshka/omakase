# frozen_string_literal: true

# ruby examples/feedback_agent.rb
require_relative "setup"

class FeedbackAgent < ApplicationAgent
  instructions "You analyze customer feedback."
  strategy :predict

  generates :analyze do
    string :sentiment, enum: %w[positive negative neutral mixed]
    array :topics, of: :string
    string :summary
  end
end

pp FeedbackAgent.analyze(text: "Great product, but shipping was slow")
