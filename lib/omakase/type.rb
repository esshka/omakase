# frozen_string_literal: true

module Omakase
  # A return type that is a Ruby class: the model builds the object in code and
  # hands the object itself back, so nothing goes through JSON.
  class Type
    def initialize(klass)
      @klass = klass
    end

    def describe = "a #{@klass}"

    def take(value)
      return value if value.is_a?(@klass)

      raise ContractError, "expected #{describe}, got #{value.class}"
    end

    def definition
      raise Error, "returns: #{@klass} needs the :code_act strategy — the model has to build the object in code"
    end

    alias_method :json, :definition
  end
end
