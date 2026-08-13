# frozen_string_literal: true

# ruby examples/memory_agent.rb
require_relative "setup"

# The chat provider and the embedding provider are separate choices. OpenRouter
# serves embeddings but does not list the models, so this one is named on trust.
Omakase.embedder = lambda do |text|
  RubyLLM.embed(text, model: ENV.fetch("EMBEDDING_MODEL", "qwen/qwen3-embedding-4b"),
    provider: :openrouter, assume_model_exists: true).vectors
end

class SupportAgent < ApplicationAgent
  instructions "You answer customers about this shop, in one sentence."
  memory

  generates :answer, "Answer the question. Recall what you know before answering.", returns: :string
end

agent = SupportAgent.new
agent.remember("Shipping to Canada takes three weeks.")
agent.remember("Refunds are processed within five days.")

puts agent.answer(question: "How long until my order reaches Toronto?")

# The store is a field, so what it learned outlives the process.
resumed = Marshal.load(Marshal.dump(agent))
puts resumed.answer(question: "And if I want my money back instead?")
