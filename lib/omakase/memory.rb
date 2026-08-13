# frozen_string_literal: true

module Omakase
  # Recall by meaning rather than by key: text goes in, the closest of it comes
  # back out. The embeddings are RubyLLM's and the search is a dot product over
  # an array — enough for the few hundred things one agent learns about its
  # work. Past that it is your database's job (pgvector, the `neighbor` gem),
  # and this is the interface to reimplement against it.
  class Memory
    def initialize = @entries = {}

    # Keyed by the text, so remembering the same thing twice costs one entry.
    def remember(text)
      @entries[text] ||= unit(Omakase.embedder.call(text))
      text
    end

    def recall(query, limit: 5)
      return [] if empty?

      vector = unit(Omakase.embedder.call(query))
      @entries.max_by(limit) { |_, remembered| dot(vector, remembered) }.map(&:first)
    end

    def size = @entries.size

    def empty? = @entries.empty?

    private

    def dot(one, other) = one.zip(other).sum { |a, b| a * b }

    # Unit vectors, so the dot product is the cosine and lengths cannot skew it.
    def unit(vector)
      norm = Math.sqrt(vector.sum { |value| value * value })
      norm.zero? ? vector : vector.map { |value| value / norm }
    end
  end
end
