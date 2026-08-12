# frozen_string_literal: true

require "dotenv/load"
require_relative "../lib/omakase"

Omakase.configure_from_env

# Rails-style base class: every agent inherits the model configuration. Point
# MODEL and PROVIDER at any provider RubyLLM supports.
class ApplicationAgent < Omakase::Agent
  model ENV.fetch("MODEL", "meta/muse-glimmer-30b"),
    provider: ENV.fetch("PROVIDER", "openrouter").to_sym
end
