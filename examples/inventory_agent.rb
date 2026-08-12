# frozen_string_literal: true

# ruby examples/inventory_agent.rb
require_relative "setup"

class InventoryAgent < ApplicationAgent
  instructions "You check inventory."

  STOCK = {
    "apple" => {stock: 50, price: 0.75},
    "banana" => {stock: 30, price: 0.50},
    "orange" => {stock: 0, price: 0.80}
  }.freeze

  describe "Units of an item on hand"
  def stock_of(item) = STOCK.dig(item, :stock) || 0

  describe "Unit price of an item"
  def price_of(item) = STOCK.dig(item, :price) || 0.0

  generates :can_fulfill_order, "Decide whether the order fits the budget and is in stock." do
    boolean :can_fulfill
    number :total_cost
    array :unavailable, of: :string
  end
end

pp InventoryAgent.can_fulfill_order(items: %w[apple banana orange], budget: 5.0)
