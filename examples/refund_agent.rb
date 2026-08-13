# frozen_string_literal: true

# A refund desk over real ActiveRecord objects, in one file.
# ruby examples/refund_agent.rb
require "active_record"
require_relative "setup"

# --- db/schema.rb ------------------------------------------------------------
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :orders do |t|
    t.string :email
    t.date :placed_on
  end
  create_table :items do |t|
    t.belongs_to :order
    t.string :name
    t.float :price
  end
end

class Order < ActiveRecord::Base
  has_many :items
  def total = items.sum(&:price)
end

class Item < ActiveRecord::Base
  belongs_to :order
end

# keyword_init, so the model cannot transpose the fields silently — a wrong
# name raises, and it fixes that inside the same loop.
# standard:disable Style/RedundantStructKeywordInit -- it is not redundant here:
# without it a plain Struct takes positional arguments, and a model that transposes
# them would be accepted silently. This way the mistake raises, and it gets fixed in loop.
Refund = Struct.new(:order_id, :amount, :reason, keyword_init: true)
# standard:enable Style/RedundantStructKeywordInit

order = Order.create!(email: "ada@example.com", placed_on: Date.today - 9)
order.items.create!([{name: "Stoneware mug", price: 34.0}, {name: "Shipping", price: 5.9}])
Order.create!(email: "ada@example.com", placed_on: Date.today - 120)
  .items.create!(name: "Cast iron pan", price: 89.0)

# --- app/agents/refund_agent.rb ----------------------------------------------
class RefundAgent < ApplicationAgent
  instructions "You are the refund desk of an online shop. Decide from the customer’s own orders."

  describe "Every order this customer placed, newest first. An Order has placed_on, items and total"
  def orders_for(email) = Order.where(email:).order(placed_on: :desc)

  describe "What the policy says about a topic, such as :damage or :late"
  def policy_on(topic) = POLICY.fetch(topic.to_sym, "Refunds are allowed within 30 days.")

  POLICY = {
    damage: "Damaged goods are refunded in full, including shipping, within 90 days."
  }.freeze

  generates :decide, "Decide this refund, and name the policy you applied.", returns: Refund
end

pp RefundAgent.decide(email: "ada@example.com", complaint: "the mug arrived cracked")
