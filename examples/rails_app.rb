# frozen_string_literal: true

# A whole Rails app in one file: POST /triage runs an agent and renders its answer.
# ruby examples/rails_app.rb
require "action_controller/railtie"
require "rack/mock_request"
require_relative "setup"

# --- config/initializers/omakase.rb ------------------------------------------
Omakase.configure do |config|
  config.request_timeout = 60
  config.instrumenter = ActiveSupport::Notifications
end

ActiveSupport::Notifications.subscribe("chat.ruby_llm") do |event|
  usage = event.payload
  puts "[llm] #{usage[:model]} #{event.duration.round}ms in=#{usage[:input_tokens]} out=#{usage[:output_tokens]}"
end

# --- app/agents/support_agent.rb ---------------------------------------------
class SupportAgent < ApplicationAgent
  instructions "You are a support agent for an online shop. Refunds are allowed within 30 days."
  strategy :predict

  generates :triage, "Classify the customer message against the shop's policy." do
    string :severity, enum: %w[low medium high]
    boolean :refund_eligible
    string :summary
  end
end

# --- app/controllers/triage_controller.rb ------------------------------------
class TriageController < ActionController::API
  def create
    render json: SupportAgent.triage(message: params.require(:message))
  rescue Omakase::ProviderError => e
    render json: {error: e.message}, status: :bad_gateway
  end
end

# --- config/application.rb ---------------------------------------------------
class Shop < Rails::Application
  config.root = __dir__
  config.eager_load = false
  config.secret_key_base = "for-the-example"
  config.logger = Logger.new(IO::NULL)
  config.hosts.clear

  routes.append { post "/triage" => "triage#create" }
end

Shop.initialize!

# Instead of booting a server: one request, in process.
response = Rack::MockRequest.new(Shop).post("/triage",
  params: {message: "It arrived cracked. I want my money back."})

puts response.status, response.body
