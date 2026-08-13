# frozen_string_literal: true

module Omakase
  # An MCP server's tools, as methods on the agent — so generated code calls a
  # remote tool the same way it calls anything else the agent exposes.
  module MCP
    module_function

    def attach(agent_class, client)
      client.tools.each do |tool|
        name = method_name(tool)
        # A remote tool list must not quietly shadow a capability the agent already has.
        raise Error, "#{agent_class} already has ##{name}" if Capabilities.names(agent_class).include?(name)

        agent_class.describe(description(tool))
        # nil is how a model leaves an argument out; MCP servers reject it.
        agent_class.define_method(name) { |**arguments| MCP.result(tool.execute(**arguments.compact)) }
      end
      client
    end

    # Tool names may hold characters a Ruby method name cannot.
    def method_name(tool) = tool.name.tr("-", "_").to_sym

    # ponytail: text only — an image or audio result is dropped.
    def result(value)
      raise Error, value[:error] if value.is_a?(Hash) && value[:error]

      value.to_s
    end

    # The signature is `**arguments`, so what those arguments are goes here.
    def description(tool)
      schema = tool.params_schema || {}
      required = schema["required"] || []
      arguments = (schema["properties"] || {}).map do |name, property|
        "#{name}: #{property["type"]}#{" (required)" if required.include?(name)}"
      end
      text = tool.description.to_s.gsub(/\s+/, " ").strip
      [text, ("Arguments — #{arguments.join(", ")}" if arguments.any?)].compact.join(" ")
    end
  end
end
