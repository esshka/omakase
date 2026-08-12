# frozen_string_literal: true

module Omakase
  # How a generation method gets its answer. Named ones are looked up by symbol
  # (`strategy :predict`); anything that responds to `call(request)` also works,
  # which is the seam for your own.
  module Strategies
    module_function

    def fetch(strategy)
      return strategy if strategy.respond_to?(:call)

      const_get(strategy.to_s.split("_").map(&:capitalize).join)
    rescue NameError
      raise Error, "unknown strategy #{strategy.inspect}"
    end
  end
end
