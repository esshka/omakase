# frozen_string_literal: true

# Plain Ruby orchestrating two generated methods, over per-instance state.
# ruby examples/support_agent.rb
require_relative "setup"

Order = Data.define(:id, :item, :delivered_days_ago)

class SupportAgent < ApplicationAgent
  instructions "You are a support agent for an online shop. Refunds are allowed within 30 days."

  def initialize(orders, **options)
    super(**options)
    @orders = orders
  end

  def handle(order_id:, message:)
    ticket = triage(message:, order: @orders.fetch(order_id))
    {**ticket, reply: reply(message:, ticket:)}
  end

  generates :triage, "Classify the customer message against the order.", strategy: :predict do
    string :severity, enum: %w[low medium high]
    boolean :refund_eligible
    string :summary
  end

  generates :reply, "Write the customer a two-sentence reply.", strategy: :predict
end

orders = {"A-1" => Order.new(id: "A-1", item: "Espresso machine", delivered_days_ago: 9)}

pp SupportAgent.new(orders).handle(order_id: "A-1", message: "It arrived cracked. I want my money back.")
