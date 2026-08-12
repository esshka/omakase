# frozen_string_literal: true

# The model meets objects it has never seen and inspects them in Ruby.
# ruby examples/warehouse_agent.rb
require_relative "setup"

Artwork = Data.define(:title, :appraisal)
Holding = Data.define(:ticker, :shares, :price) do
  def total_value = shares * price
end
Jewelry = Data.define(:name, :carats, :rate_per_carat) do
  def worth = carats * rate_per_carat
end

class WarehouseAgent < ApplicationAgent
  instructions "You appraise warehouse items. Their types differ, so inspect what you get."

  ITEMS = {
    "ART-001" => Artwork.new(title: "Starry Night Print", appraisal: {value: 15_000.0, currency: "USD"}),
    "STK-001" => Holding.new(ticker: "NVDA", shares: 100, price: 875.50),
    "JWL-001" => Jewelry.new(name: "Diamond Ring", carats: 2.5, rate_per_carat: 8_000.0)
  }.freeze

  describe "Item for an id — the type varies"
  def item(id) = ITEMS.fetch(id)

  generates :appraise, "Dollar value of the item with this id.", returns: :number
end

pp WarehouseAgent::ITEMS.keys.to_h { |id| [id, WarehouseAgent.appraise(item_id: id)] }
