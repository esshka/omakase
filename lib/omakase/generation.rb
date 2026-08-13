# frozen_string_literal: true

module Omakase
  # A method the agent declares but does not implement: the prompt is its body,
  # the schema is its return type, the strategy is how it gets there. A model
  # named here overrides the class's, for this method alone.
  Generation = Data.define(:name, :prompt, :schema, :strategy, :model)
end
