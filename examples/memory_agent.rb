# frozen_string_literal: true

# ruby examples/memory_agent.rb
# Needs a provider that serves embeddings — OPENAI_API_KEY, or a local Ollama
# with an embedding model. RubyLLM's default is text-embedding-3-small.
require_relative "setup"

# The chat provider and the embedding provider need not be the same one.
Omakase.configure { |config| config.default_embedding_model = ENV["EMBEDDING_MODEL"] } if ENV["EMBEDDING_MODEL"]

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
