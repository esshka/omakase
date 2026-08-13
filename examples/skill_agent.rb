# frozen_string_literal: true

# ruby examples/skill_agent.rb
require_relative "setup"

# A skill is a SKILL.md directory: its description is listed with the agent's
# capabilities, and the body only reaches the model if it asks for it.
class CommitAgent < ApplicationAgent
  instructions "You name commits for a Ruby library."

  skill File.expand_path("skills/commit-style", __dir__)

  generates :subject_for, "Write the commit subject for this change.", returns: :string
end

puts CommitAgent.subject_for(change: "MCP server tools are now defined as methods on the agent, " \
  "so generated code can call them; adds lib/omakase/mcp.rb, a macro, tests and an example.")
