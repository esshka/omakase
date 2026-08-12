# frozen_string_literal: true

module Omakase
  # The declared return type, enforced by the provider. A schema whose only
  # property is `result` unwraps to that value.
  class Schema
    RESULT = :result
    SCALARS = %i[string integer number boolean].freeze

    def self.define(returns: nil, &block)
      return new(Schematist::Schema.create(&block)) if block

      type = returns || :string
      raise Error, "returns: must be one of #{SCALARS.join(", ")} (or pass a block)" unless SCALARS.include?(type)

      new(Schematist::Schema.create { public_send(type, RESULT) })
    end

    attr_reader :definition

    def initialize(definition)
      @definition = definition
    end

    def json = definition.new.to_json_schema

    def cast(content)
      raise Error, "expected JSON matching #{JSON.generate(json)}, got #{content.inspect}" unless content.is_a?(Hash)

      data = RubyLLM::Utils.deep_symbolize_keys(content)
      return data unless wrapped?

      data.fetch(RESULT) { raise Error, "missing \"result\" in #{data.inspect}" }
    end

    def wrapped? = definition.properties.keys == [RESULT]
  end
end
