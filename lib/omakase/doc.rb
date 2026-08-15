# frozen_string_literal: true

module Omakase
  # What an object offers, for a model that has never seen its type: what the
  # object's own classes define, not what Ruby gives everything.
  module Doc
    CORE = [Object, Kernel, BasicObject, Struct, Data, Enumerable, Comparable].freeze

    module_function

    # A framework's base class defines hundreds of methods the model has no use
    # for. What it wants is what this class adds — its columns, its associations,
    # and the methods you wrote.
    def boundary = defined?(ActiveRecord::Base) ? [*CORE, ActiveRecord::Base] : CORE

    def of(object)
      return of_class(object) if object.is_a?(Module)

      [object.class.to_s, *signatures(object.class) { |name| object.method(name) }, *state(object)].join("\n")
    end

    # A class, not an instance: what one would have. The model asks this before it
    # builds an object of a type it has only been told the name of.
    def of_class(klass)
      [klass.to_s, *signatures(klass) { |name| klass.instance_method(name) }, *columns(klass)].join("\n")
    end

    def columns(klass)
      return [] unless klass.respond_to?(:column_names)

      klass.column_names.map { |name| "  #{name}" }
    end

    # An object that answers `attributes` says what it holds better than its
    # instance variables do — and a record's columns are state, not API.
    def state(object)
      values = object.respond_to?(:attributes) ? object.attributes : ivars(object)
      values.map { |name, value| "  #{name} = #{value.inspect}" }
    end

    def ivars(object) = object.instance_variables.to_h { |name| [name, object.instance_variable_get(name)] }

    def signatures(klass, &getter)
      klass.ancestors
        .take_while { |mod| !boundary.include?(mod) }
        .reject { |mod| mod.to_s.end_with?("GeneratedAttributeMethods") }
        .flat_map { |mod| mod.public_instance_methods(false) }
        .uniq.sort
        .reject { |name| name.match?(/\A_|_associated_records_for_/) }
        .map { |name| "  #{name}(#{Capabilities.parameters(getter.call(name))})" }
    end
  end
end
