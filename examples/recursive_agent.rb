# frozen_string_literal: true

# A tree of work: the model names the parts, a fresh agent takes each part, and
# Ruby decides when to stop. One generation per node, and the depth is a number
# in this file rather than a sentence in a prompt.
# ruby examples/recursive_agent.rb
require_relative "setup"

class PlannerAgent < ApplicationAgent
  instructions "You break work into parts. Each part is one clear piece of work, named in a few words."
  strategy :predict

  def initialize(depth:, **options)
    super(**options)
    @depth = depth
  end

  # The recursion is here, in plain Ruby, where you can read the bound. The model
  # is asked one question per node and never decides how far this goes.
  def plan(task)
    return [] if @depth.zero?

    split(task:)[:parts].map { |part| [part, deeper.plan(part)] }
  end

  generates :split, "Name the two or three parts this task breaks into." do
    array :parts, of: :string
  end

  private

  # A fresh agent per branch. Sibling branches then share no state, and no object
  # re-enters a generation it is already inside — which is refused, on purpose.
  def deeper = self.class.new(depth: @depth - 1, chat: @chat)
end

def show(tree, indent = 1)
  tree.each do |task, parts|
    puts "#{"  " * indent}#{task}"
    show(parts, indent + 1)
  end
end

task = "launch a small online shop"
puts task
show(PlannerAgent.new(depth: 2).plan(task))
