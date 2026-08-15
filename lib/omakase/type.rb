# frozen_string_literal: true

module Omakase
  # A return type that is a Ruby class: the model builds the object in code and
  # hands the object itself back, so nothing goes through JSON.
  class Type
    def initialize(klass)
      @klass = klass
    end

    # A Struct or Data says what it holds, and the model needs that to build one:
    # `Refund.new(order_id:, amount:, reason:)` beats `a Refund`.
    def describe
      return "a #{@klass}" unless @klass.respond_to?(:members)

      "#{@klass}.new(#{@klass.members.map { |name| "#{name}:" }.join(", ")})"
    end

    # Only code can build it, so :predict is not a fallback.
    def code_only? = true

    def take(value)
      raise ContractError, "expected #{describe}, got #{value.class}" unless value.is_a?(@klass)

      well_formed(value)
    end

    def definition
      raise Error, "returns: #{@klass} needs the :code_act strategy — the model has to build the object in code"
    end

    alias_method :json, :definition

    private

    # An object that can say whether it is well-formed gets asked — ActiveModel,
    # ActiveRecord, anything of that shape. The refusal reaches the model as an
    # observation, so your own validations are what it has to satisfy, and they
    # stay where you wrote them instead of being retyped into a prompt.
    def well_formed(value)
      return value unless value.respond_to?(:valid?) && value.respond_to?(:errors)
      return value if value.valid?

      raise ContractError, "#{@klass} is invalid: #{value.errors.full_messages.join("; ")}"
    end
  end
end
