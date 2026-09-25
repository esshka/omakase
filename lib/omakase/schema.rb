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
      content = parse(content) if content.is_a?(String)
      raise ContractError, "expected JSON matching #{JSON.generate(json)}, got #{content.inspect}" unless content.is_a?(Hash)

      data = symbolize(content)
      take(wrapped? ? data.fetch(RESULT) { raise ContractError, %(missing "result" in #{data.inspect}) } : data)
    end

    # From a Ruby value the generated code computed.
    def take(value)
      return demand(value, properties.fetch("result")["type"]) if wrapped?
      raise ContractError, "expected #{describe}, got #{value.inspect}" unless value.is_a?(Hash)

      data = symbolize(value)
      problem = object_mismatch(data, json, nil)
      raise ContractError, "#{problem} — expected #{describe}" if problem

      data
    end

    def wrapped? = definition.properties.keys == [RESULT]

    private

    def properties = json.fetch("properties")

    # RubyLLM 2 hands structured output back as a JSON string. Not JSON stays a
    # String, so cast reports what the model actually said.
    def parse(content)
      JSON.parse(content)
    rescue JSON::ParserError
      content
    end

    def symbolize(value)
      case value
      when Hash then value.to_h { |key, item| [key.respond_to?(:to_sym) ? key.to_sym : key, symbolize(item)] }
      when Array then value.map { |item| symbolize(item) }
      else value
      end
    end

    def demand(value, type)
      raise ContractError, "expected <#{type}>, got #{value.inspect}" unless type?(value, type)

      value
    end

    def type?(value, type)
      case type
      when "boolean" then [true, false].include?(value)
      when "null" then value.nil?
      when Array then type.any? { |each| type?(value, each) }
      else value.is_a?(RUBY_TYPES.fetch(type, BasicObject))
      end
    end

    # The first place a nested value breaks its schema, as a path the model can fix.
    def mismatch(value, spec, path)
      return "#{path}: expected <#{Array(spec["type"]).join("|")}>, got #{value.inspect}" if spec["type"] && !type?(value, spec["type"])
      return "#{path}: expected one of #{spec["enum"].inspect}, got #{value.inspect}" if spec["enum"] && !spec["enum"].include?(value)

      case value
      when Array then value.each_with_index.filter_map { |item, i| mismatch(item, spec["items"], "#{path}[#{i}]") if spec["items"] }.first
      when Hash then object_mismatch(value, spec, path)
      end
    end

    # An optional field left nil is a field left out, which is allowed.
    def object_mismatch(value, spec, path)
      required = Array(spec["required"])
      missing = required.map(&:to_sym) - value.keys
      return [path, "missing #{missing.join(", ")}"].compact.join(": ") if missing.any?

      Hash(spec["properties"]).filter_map do |name, child|
        field = value[name.to_sym]
        next if field.nil? && !required.include?(name)

        mismatch(field, child, [path, name].compact.join(".")) if value.key?(name.to_sym)
      end.first
    end
  end
end
