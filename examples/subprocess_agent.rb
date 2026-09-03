# frozen_string_literal: true

# Generated code in a child process: a crash or a runaway loop there is an
# observation here, and this process stays up. Watch the trace — a bad row
# raises in the child, the model reads the line, fixes it, and finishes.
# ruby examples/subprocess_agent.rb
require_relative "setup"

Omakase.executor = Omakase::Executor::Subprocess
Omakase.listener = Omakase::Trace.new

class LedgerAgent < ApplicationAgent
  instructions "You reconcile a day's card transactions against the bank settlement."

  # Rows as they arrive from the export: amounts are strings, one is missing,
  # one refund is negative, and the settlement is in cents.
  TRANSACTIONS = [
    {id: "tx-1", amount: "19.99", status: "captured"},
    {id: "tx-2", amount: "5.00", status: "captured"},
    {id: "tx-3", amount: nil, status: "voided"},
    {id: "tx-4", amount: "-7.50", status: "refunded"},
    {id: "tx-5", amount: "42.10", status: "captured"}
  ].freeze

  SETTLEMENT_CENTS = 5_959

  describe "The day's transactions, one hash per row"
  def transactions = TRANSACTIONS

  describe "What the bank says it settled, in cents"
  def settlement_cents = SETTLEMENT_CENTS

  generates :reconcile, "Does the captured-minus-refunded total match the settlement? Name any gap." do
    boolean :balanced
    integer :expected_cents
    integer :gap_cents
    array :suspects, of: :string
  end
end

pp LedgerAgent.reconcile
