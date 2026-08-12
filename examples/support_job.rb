# frozen_string_literal: true

# Generation off the request thread: one ActiveJob per ticket, run concurrently.
# ruby examples/support_job.rb
require "active_job"
require_relative "setup"

class SupportAgent < ApplicationAgent
  instructions "You are a support agent for an online shop. Refunds are allowed within 30 days."
  strategy :predict

  generates :triage, "Classify the customer message against the shop's policy." do
    string :severity, enum: %w[low medium high]
    boolean :refund_eligible
    string :summary
  end
end

class TriageJob < ActiveJob::Base
  # Jobs move data, not objects — arguments and results have to serialize.
  def perform(ticket_id, message)
    triage = SupportAgent.triage(message:)
    puts "#{ticket_id}: #{triage[:severity]} refund=#{triage[:refund_eligible]} — #{triage[:summary]}"
  end
end

ActiveJob::Base.queue_adapter = :async
ActiveJob::Base.logger = Logger.new(IO::NULL)

{
  "A-1" => "It arrived cracked. I want my money back.",
  "A-2" => "Where is my order? It has been three weeks.",
  "A-3" => "Just saying thanks, the grinder is lovely."
}.each { |id, message| TriageJob.perform_later(id, message) }

ActiveJob::Base.queue_adapter.shutdown # wait for the pool to drain
