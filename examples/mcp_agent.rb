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

  describe "The absolute path of the project"
  def root = File.expand_path("..", __dir__)

  generates :summarize, "Read the project's README and say in one sentence what it is.", returns: :string
end

puts DocsAgent.summarize
