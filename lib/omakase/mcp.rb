# frozen_string_literal: true

module Omakase
  # An MCP server's tools, as methods on the agent — so generated code calls a
  # remote tool the same way it calls anything else the agent exposes.
  module MCP
    MUTEX = Mutex.new

    class << self
      def client_factory=(factory)
        unless factory.nil? || factory.respond_to?(:call)
          raise Error, "client_factory must answer call, got #{factory.class}"
        end

        @client_factory = factory
      end

      def client_factory
        @client_factory || ->(name, **options) {
          require "ruby_llm/mcp"
          RubyLLM::MCP.add_client(name: name.to_s, **options)
        }
      end
    end

    module_function

    def defer(agent_class, name, options)
      servers(agent_class)[name.to_sym] = options
    end

    def ensure(agent_class)
      return unless pending?(agent_class)

      MUTEX.synchronize do
        return unless pending?(agent_class)

        agent_class.ancestors.take_while { |mod| mod != Agent }.reverse_each do |klass|
          attach_pending(klass) if klass.is_a?(Class)
        end
      end
    end

    def pending?(agent_class)
      agent_class.ancestors.take_while { |mod| mod != Agent }.any? do |mod|
        mod.is_a?(Class) && (servers(mod).keys - attached(mod)).any?
      end
    end

    def attach_pending(klass)
      servers(klass).each do |name, options|
        next if attached(klass).include?(name)

        # A down sidecar stays unattached. The generate still runs. Next ensure retries.
        client = begin
          client_factory.call(name, **options)
        rescue
          next
        end
        attach(klass, client)
        attached(klass) << name
      end
    end

    def attach(agent_class, client)
      defined = []
      client.tools.each do |tool|
        name = method_name(tool)
        # A remote tool list must not quietly shadow a capability the agent already has.
        raise Error, "#{agent_class} already has ##{name}" if Capabilities.names(agent_class).include?(name)

        agent_class.describe(description(tool))
        # nil is how a model leaves an argument out; MCP servers reject it.
        agent_class.define_method(name) { |**arguments| MCP.result(tool.execute(**arguments.compact)) }
        defined << name
      end
      client
    rescue
      # Else the next ensure dies on "already has #name".
      defined.each do |name|
        agent_class.send(:remove_method, name)
        agent_class.descriptions.delete(name)
      end
      agent_class.instance_variable_set(:@pending_description, nil)
      client.close if client.respond_to?(:close)
      raise
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

    def servers(klass)
      klass.instance_variable_get(:@mcp_servers) || klass.instance_variable_set(:@mcp_servers, {})
    end

    def attached(klass)
      klass.instance_variable_get(:@mcp_attached) || klass.instance_variable_set(:@mcp_attached, [])
    end
  end
end
