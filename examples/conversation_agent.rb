# frozen_string_literal: true

# Multi-turn support with nothing kept in the process: identity is a row, state is
# your tables, and the agent is a value — built for one turn and thrown away. Each
# turn here crosses a queue, so the only thing that travels is an id and a String.
# ruby examples/conversation_agent.rb
require "active_record"
require "active_job"
require "tmpdir"
require_relative "setup"

# A file, not :memory: — the worker thread opens its own connection, and an
# in-memory database would hand it a different, empty one. That is the point.
DATABASE = File.join(Dir.tmpdir, "omakase-conversation.sqlite3")
FileUtils.rm_f(DATABASE)
at_exit { FileUtils.rm_f(DATABASE) }

# --- db/schema.rb ------------------------------------------------------------
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DATABASE)
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:conversations) { |t| t.string :email }
  create_table :messages do |t|
    t.belongs_to :conversation
    t.string :role
    t.text :content
    t.timestamps
  end
  create_table :orders do |t|
    t.string :email
    t.string :item
    t.date :placed_on
  end
end

class Conversation < ActiveRecord::Base
  has_many :messages
  def orders = Order.where(email:)
end

class Message < ActiveRecord::Base
  belongs_to :conversation
end

class Order < ActiveRecord::Base
end

# --- app/agents/support_agent.rb ---------------------------------------------
class SupportAgent < ApplicationAgent
  instructions "You are the support desk. Answer from the customer's own data, in one sentence."

  def initialize(conversation, **options)
    super(**options)
    @conversation = conversation
  end

  # The whole of multi-turn: history is context, read back from rows every turn.
  def context
    @conversation.messages.order(:created_at).last(30)
      .map { |message| "#{message.role}: #{message.content}" }.join("\n")
  end

  describe "Every order this customer placed, newest first. An Order has item and placed_on"
  def orders = @conversation.orders.order(placed_on: :desc)

  generates :reply, "Answer the customer's last message.", returns: :string
end

# --- app/jobs/turn_job.rb ----------------------------------------------------
class TurnJob < ActiveJob::Base
  # In a real app: `limits_concurrency key: ->(conversation) { conversation }`, so one
  # turn per conversation at a time. The lock belongs in the queue — `with_lock` around
  # a generation would hold a transaction open for every provider round-trip.
  def perform(conversation_id, message)
    conversation = Conversation.find(conversation_id)
    conversation.messages.create!(role: "user", content: message)
    reply = SupportAgent.new(conversation).reply
    conversation.messages.create!(role: "assistant", content: reply)
  end
end

ActiveJob::Base.queue_adapter = :async
ActiveJob::Base.logger = Logger.new(IO::NULL)

Order.create!(email: "ada@example.com", item: "Stoneware mug", placed_on: Date.today - 9)
Order.create!(email: "ada@example.com", item: "Cast iron pan", placed_on: Date.today - 120)
conversation_id = Conversation.create!(email: "ada@example.com").id

# Two turns, and between them this process keeps nothing: no agent, no chat, no
# history. Only the id crosses, the way it would to a worker on another machine.
["Hi — the mug I bought arrived cracked.", "And what about the pan?"].each do |message|
  TurnJob.perform_later(conversation_id, message)
  ActiveJob::Base.queue_adapter.shutdown          # drain: one turn at a time
  ActiveJob::Base.queue_adapter = :async
end

Conversation.find(conversation_id).messages.order(:created_at)
  .each { |message| puts "#{message.role}: #{message.content}" }
