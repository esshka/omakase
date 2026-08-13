# frozen_string_literal: true

module Omakase
  # The declared return type, enforced by the provider. A schema whose only
  # property is `result` unwraps to that value.
  class Schema
    RESULT = :result
    SCALARS = %i[string integer number boolean].freeze
    RUBY_TYPES = {
      "string" => String, "integer" => Integer, "number" => Numeric,
      "array" => Array, "object" => Hash
    }.freeze

    def self.define(returns: nil, &block)
      # Two contracts in one declaration: one of them would be dropped, silently.
      raise Error, "returns: and a schema block are two different contracts — declare one" if returns && block

      return new(Schematist::Schema.create(&block)) if block
      return Type.new(returns) if returns.is_a?(Module)

      type = returns || :string
      raise Error, "returns: must be one of #{SCALARS.join(", ")}, a class, or a block" unless SCALARS.include?(type)

      new(Schematist::Schema.create { public_send(type, RESULT) })
    end

    attr_reader :definition

    def initialize(definition)
      @definition = definition
    end

    def json = @json ||= definition.new.to_json_schema

    def code_only? = false

    # The shape, in the shorthand the model writes back: `{city: <string>}`.
    def describe
      return "<#{properties.fetch("result")["type"]}>" if wrapped?

      "{#{properties.map { |name, spec| "#{name}: <#{spec["type"]}>" }.join(", ")}}"
    end

    # From the provider's JSON: unwrap first, then hold it to the contract.
    def cast(content)
      raise ContractError, "expected JSON matching #{JSON.generate(json)}, got #{content.inspect}" unless content.is_a?(Hash)

      data = RubyLLM::Utils.deep_symbolize_keys(content)
      take(wrapped? ? data.fetch(RESULT) { raise ContractError, %(missing "result" in #{data.inspect}) } : data)
    end

    # From a Ruby value the generated code computed.
    def take(value)
      return demand(value, properties.fetch("result")["type"]) if wrapped?
      raise ContractError, "expected #{describe}, got #{value.inspect}" unless value.is_a?(Hash)

      data = RubyLLM::Utils.deep_symbolize_keys(value)
      missing = json.fetch("required").map(&:to_sym) - data.keys
      raise ContractError, "missing #{missing.join(", ")} — expected #{describe}" if missing.any?

      data
    end

    def wrapped? = definition.properties.keys == [RESULT]

    private

    def properties = json.fetch("properties")

    def demand(value, type)
      matched = (type == "boolean") ? [true, false].include?(value) : value.is_a?(RUBY_TYPES.fetch(type))
      raise ContractError, "expected <#{type}>, got #{value.inspect}" unless matched

      value
    end
  end
end
