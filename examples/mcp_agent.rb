# frozen_string_literal: true

# ruby examples/mcp_agent.rb
require_relative "setup"

# An MCP server's tools land on the agent as methods, so generated code calls
# them alongside the agent's own. This one serves the repo's own directory.
class DocsAgent < ApplicationAgent
  instructions <<~TEXT
    You look things up in the project files, then answer in your own words.
    finish() is the answer. Never finish with raw file contents.
  TEXT

  mcp :files,
    transport_type: :stdio,
    config: {command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", File.expand_path("..", __dir__)]}

  describe "The absolute path of the project"
  def root = File.expand_path("..", __dir__)

  generates :summarize,
    "What is this project? One short sentence. Read README.md, then finish with your sentence — not the file.",
    returns: :string
end

puts DocsAgent.summarize
