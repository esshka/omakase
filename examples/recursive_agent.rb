# frozen_string_literal: true

# A tree that already exists: one agent per comment, folding a thread from the
# leaves up. The recursion belongs to the data — a comment with no replies is the
# base case — so nothing has to invent how deep this goes.
# ruby examples/recursive_agent.rb
require "active_record"
require_relative "setup"

# --- db/schema.rb ------------------------------------------------------------
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :comments do |t|
    t.belongs_to :parent
    t.string :author
    t.text :body
  end
end

class Comment < ActiveRecord::Base
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id
end

# --- app/agents/thread_agent.rb ----------------------------------------------
class ThreadAgent < ApplicationAgent
  instructions "You sum up a discussion for someone who has not read it. One sentence, no preamble."
  strategy :predict

  def initialize(comment, **options)
    super(**options)
    @comment = comment
  end

  # A leaf is its own summary, so the model is asked only where there is
  # something to fold. Each branch gets its own agent and shares no state.
  def roll_up
    return said if @comment.replies.empty?

    summarise(comment: said, replies: @comment.replies.map { |reply| self.class.new(reply, chat: @chat).roll_up })
  end

  generates :summarise, "Sum up this comment together with the replies it drew.", returns: :string

  private

  def said = "#{@comment.author}: #{@comment.body}"
end

root = Comment.create!(author: "ada", body: "Ship the mugs in a box or a sleeve?")
box = root.replies.create!(author: "linus", body: "A box. Sleeves crack in transit.")
box.replies.create!(author: "grace", body: "Agreed — three returns last month, all sleeves.")
root.replies.create!(author: "alan", body: "Boxes cost 40 cents more each.")

puts ThreadAgent.new(root).roll_up
