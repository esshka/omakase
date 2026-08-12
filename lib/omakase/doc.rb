# frozen_string_literal: true

module Omakase
  # What an object offers, for a model that has never seen its type: what the
  # object's own classes define, not what Ruby gives everything.
  module Doc
    CORE = [Object, Kernel, BasicObject, Struct, Data, Enumerable, Comparable].freeze

    module_function

    def of(object)
      state = object.instance_variables.map { |name| "  #{name} = #{object.instance_variable_get(name).inspect}" }
      [object.class.to_s, *signatures(object), *state].join("\n")
    end

    def signatures(object)
      object.class.ancestors
        .take_while { |mod| !CORE.include?(mod) }
        .flat_map { |mod| mod.public_instance_methods(false) }
        .uniq.sort
        .map { |name| "  #{name}(#{Capabilities.parameters(object.method(name))})" }
    end
  end
end
