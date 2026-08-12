# Omakase

A light agent framework — about 350 lines of library. *Omakase* (お任せ): you name what you want,
the rest is left to the chef.

The whole philosophy: **an agent is an object**. Its fields are state, its methods are what the
model can call, and the methods it *declares without a body* are written by the model at runtime —
the method name and prompt are the specification, the schema is the contract.

```ruby
class InventoryAgent < ApplicationAgent
  instructions "You check inventory."

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

InventoryAgent.can_fulfill_order(items: %w[apple banana orange], budget: 5.0)
# => {can_fulfill: false, total_cost: 2.05, unavailable: ["orange"]}
```

There is no tool abstraction to keep in sync: the model writes Ruby that runs on the agent object,
reads what it printed and returned, and answers in the declared schema. Adding a tool is adding a
method; deleting one is deleting a method.

## Installation

Not published as a gem — clone it and point your `Gemfile` at the checkout, or copy `lib/` in.

```bash
git clone <this repo> && cd omakase
bundle install
```

Requires Ruby 3.2+.

## Usage

### Declaring an agent

```ruby
class ApplicationAgent < Omakase::Agent            # every agent inherits the configuration
  model "claude-sonnet-4-5"
end

class FeedbackAgent < ApplicationAgent
  instructions "You analyze customer feedback."   # the system prompt
  strategy :predict                               # :code_act (default) or :predict

  generates :summarize                            # no prompt given: the method name is the prompt
  generates :score, returns: :integer
  generates :analyze, "Analyze the feedback." do
    string :sentiment, enum: %w[positive negative neutral mixed]
    array :topics, of: :string
  end
end
```

Generation methods take keyword arguments, which are rendered into the prompt, and are callable on
the instance or on the class:

```ruby
FeedbackAgent.analyze(text: "Great product, but shipping was slow")
# => {sentiment: "mixed", topics: ["product quality", "shipping speed"]}

FeedbackAgent.new.analyze(text: "…")
```

`describe` above an ordinary method is the docstring Ruby does not have — it is what the model reads
when it decides what to call.

### Return types

The block is a [schematist](https://github.com/crmne/schematist) schema and becomes the provider's
structured-output contract, so a generation method returns validated data, never text to parse.
For a single value, name the type instead:

```ruby
generates :count_items, returns: :integer      # :string (default), :integer, :number, :boolean
```

Both forms are the same mechanism: a schema whose only property is `result` unwraps to that value.

### Models and providers

Any provider RubyLLM supports — Anthropic, OpenAI, Gemini, Bedrock, Azure, Mistral, DeepSeek, xAI,
Perplexity, OpenRouter, Ollama, GPUStack, VertexAI. Give the model id, and the provider when the id
is not one RubyLLM has in its registry:

```ruby
class ApplicationAgent < Omakase::Agent
  model "claude-sonnet-4-5"                                    # resolved from the registry
  model "meta/muse-glimmer-30b", provider: :openrouter         # taken on trust
  model "qwen3:1.7b", provider: :ollama                        # local
end
```

Naming a provider implies `assume_model_exists: true`; any other RubyLLM chat option passes through.
Subclasses inherit the setting and can override it, so one `ApplicationAgent` configures the lot.

Credentials come from the environment — one call covers every provider:

```ruby
Omakase.configure_from_env    # ANTHROPIC_API_KEY, OPENROUTER_API_KEY, OLLAMA_API_BASE, …
```

Or set them yourself; `configure` is RubyLLM's, with all of its options:

```ruby
Omakase.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.anthropic_api_key
  config.default_model = "claude-sonnet-4-5"   # used by agents that declare no model
  config.request_timeout = 120
end
```

### Testing

`Omakase::Agent.new(chat:)` takes any object that quacks like a `RubyLLM::Chat`, so agents can be
tested without a network. See `test/omakase_test.rb` for a 30-line fake that also drives the tools.

## How it works

Calling a generation method does four things:

1. **Builds a request.** `Request` carries the agent, the generation (prompt, schema, strategy), the
   keyword arguments, and a fresh chat — one conversation per call, no accumulated history.
2. **Renders the prompt.** The agent's `instructions` are the system prompt; the method's prompt and
   its arguments are the user message.
3. **Runs the strategy** (below), which is where the LLM work happens.
4. **Casts the answer.** The reply is JSON in the declared schema; `Schema#cast` symbolizes it,
   unwraps a lone `result`, and raises rather than hand back something off-contract.

### Strategies

A strategy is *how* a generation method gets its answer — one call, a code loop, your own
retry-and-critique scheme. It is an execution detail, not part of the method's contract: swapping
one for another changes cost and capability, and no caller changes.

Formally, a strategy is anything that responds to `call(request)` and returns the cast value. Two
ship with the library:

**`:predict`** — one call. The chat is configured with the instructions and the schema, the task
goes in, structured output comes back; an answer that misses the schema gets one correction
turn naming what was wrong. No code runs. Right for classification, extraction, rewriting — anything the model can answer from the prompt alone.

**`:code_act`** *(default)* — the model acts by writing Ruby. It gets one tool, `ruby`, whose code
is `instance_eval`'d on the agent, so the agent's methods and state are the API; anything printed
and the value of the last expression come back as the observation, and the loop repeats until the
model is done. A failure comes back with the line that raised, and `doc(object)` prints what an
object of an unfamiliar type offers, so the model can correct itself instead of guessing. `Capabilities` lists the agent's own methods (with their `describe` text) in the
system prompt, minus the method being written, so it cannot recurse into itself. The answer is then
taken in a second, tool-free turn, because providers fall back to prose when tools and structured
output arrive in the same request.

Set the default per agent with `strategy :predict`, per method with
`generates :triage, strategy: :predict`, or pass your own object:

```ruby
module CriticStrategy
  def self.call(request)
    draft = Omakase::Strategies::CodeAct.call(request)
    ...
  end
end

generates :plan, strategy: CriticStrategy
```

### Layout

    lib/omakase.rb                 configuration
    lib/omakase/agent.rb           the DSL: model, instructions, describe, generates
    lib/omakase/generation.rb      a declared method: prompt, schema, strategy
    lib/omakase/request.rb         one invocation of one
    lib/omakase/schema.rb          return types
    lib/omakase/capabilities.rb    the agent’s own methods, listed for the model
    lib/omakase/doc.rb             what an unfamiliar object offers, for generated code
    lib/omakase/executor.rb        runs generated Ruby against the agent
    lib/omakase/tools/ruby.rb      that executor, as a RubyLLM tool
    lib/omakase/strategies/        code_act, predict

## Examples

Copy `.env.example` to `.env` and fill in a key; `MODEL` and `PROVIDER` there pick the backend.

| File | Shows |
| --- | --- |
| [`feedback_agent.rb`](examples/feedback_agent.rb) | structured output in one call |
| [`inventory_agent.rb`](examples/inventory_agent.rb) | the agent's methods as the model's tools |
| [`warehouse_agent.rb`](examples/warehouse_agent.rb) | inspecting objects whose types are unknown |
| [`support_agent.rb`](examples/support_agent.rb) | plain Ruby orchestrating generated methods |

```bash
bundle exec rake                     # tests, no network
ruby examples/inventory_agent.rb
```

## Safety

Generated code is evaluated in-process with `instance_eval`. There is no sandbox: run agents that
execute model-written code inside a container or VM.

## Scope

Deliberately not included: tracing, events, MCP, skills, memory, async, and returning live Ruby
objects from a generation method. The seams are a strategy (`call(request)`) and RubyLLM itself.
