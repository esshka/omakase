# frozen_string_literal: true

module Omakase
  # A method the agent declares but does not implement: the prompt is its body,
  # the schema is its return type, the strategy is how it gets there.
  Generation = Data.define(:name, :prompt, :schema, :strategy)
end
