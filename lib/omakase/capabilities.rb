# frozen_string_literal: true

module Omakase
  # The agent's own methods, written out for the model. Adding a tool is adding
  # a method.
  module Capabilities
    module_function

    def of(agent_class, except: nil)
      (names(agent_class) - [except]).sort.map { |name| entry(agent_class, name) }
    end

    def names(agent_class)
      agent_class.ancestors
        .take_while { |mod| mod != Agent }
        .flat_map { |mod| mod.public_instance_methods(false) }
        .uniq
    end

    def entry(agent_class, name)
      signature = "#{name}(#{parameters(agent_class.instance_method(name))})"
      # A prompt written as a block needs an instance to read; `describe` it instead.
      prompt = agent_class.generations[name]&.prompt
      description = agent_class.descriptions[name] || (prompt unless prompt.is_a?(Proc))
      description ? "#{signature} — #{description}" : signature
    end

    def parameters(method)
      method.parameters.map do |kind, name|
        case kind
        when :key, :keyreq then "#{name}:"
        when :keyrest then "**#{name}"
        when :rest then "*#{name}"
        when :opt then "#{name} = ..."
        else name.to_s
        end
      end.join(", ")
    end
  end
end
