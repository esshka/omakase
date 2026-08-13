# frozen_string_literal: true

# ruby examples/mcp_agent.rb
require_relative "setup"

# An MCP server's tools land on the agent as methods, so generated code calls
# them alongside the agent's own. This one serves the repo's own directory.
class DocsAgent < ApplicationAgent
  instructions "You answer questions about a project by reading its files."

  mcp :files,
    transport_type: :stdio,
    config: {command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", File.expand_path("..", __dir__)]}

  generates :dependencies,
    "Read #{File.expand_path("../omakase-agents.gemspec", __dir__)} and list the gems it adds as runtime dependencies." do
    array :gems, of: :string
  end
end

pp DocsAgent.dependencies
