# Omakase

A light agent framework — about 600 lines of library. *Omakase* (お任せ): you name what you want,
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
A Ruby class works too — `returns: Ticket` — and then the method hands back the object rather than
data; see [`:code_act`](#strategies) for what that requires.

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

`Omakase::Agent.new(chat:)` takes any object that quacks like a `RubyLLM::Chat`, and one ships with
the library, so agents are tested without a network:

```ruby
chat = Omakase::FakeChat.new { {"severity" => "high", "summary" => "…"} }
assert_equal "high", SupportAgent.new(chat:).triage(message: "broken")[:severity]

# drive the tool the way a model would
chat = Omakase::FakeChat.new { |fake| fake.run("finish(stock_of(:apple))") }
```

It records `instructions`, `schema`, `tools` and `tasks`, so the prompt is assertable too.

## Rails

Agents live in `app/agents` — Rails autoloads it, and reloading is safe because everything a
generation method needs is rebuilt when the class is. [`examples/rails_app.rb`](examples/rails_app.rb)
is all of this as one runnable file: initializer, agent, controller, one request.

```ruby
# config/initializers/omakase.rb
Omakase.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.anthropic_api_key
  config.default_model = "claude-sonnet-4-5"
  config.request_timeout = 60          # RubyLLM's default is 300s — too long for a web request
  config.max_retries = 3               # transient provider failures, with backoff
  config.logger = Rails.logger
  config.instrumenter = ActiveSupport::Notifications
end
```

That last line puts every call on the notification bus, so tokens, cost and latency land in your
logs and APM without any code of ours:

```ruby
ActiveSupport::Notifications.subscribe("chat.ruby_llm") do |*, payload|
  Rails.logger.info(model: payload[:model], input: payload[:input_tokens], output: payload[:output_tokens])
end
```

A generation call takes seconds, so keep it off the request thread:

```ruby
class TriageJob < ApplicationJob
  def perform(ticket) = ticket.update!(SupportAgent.triage(message: ticket.body))
end
```

Jobs move data, not objects: arguments and results have to serialize, so a `returns: SomeClass`
answer — a live Ruby object — does not survive the trip. [`examples/support_job.rb`](examples/support_job.rb)
is the runnable version, three tickets triaged concurrently by the async adapter.

**Threads.** Puma is multi-threaded and so is this: printing from generated code goes to a
per-thread buffer, and each call gets its own chat and its own agent instance. Concurrent calls are
just threads:

```ruby
ids.map { |id| Thread.new { WarehouseAgent.appraise(item_id: id) } }.map(&:value)
```

Sharing one agent instance across threads is your business as usual — its state is yours. Do not
turn on RubyLLM's `tool_concurrency`: that runs generated code against the same agent in parallel.

**Errors.** Everything raised at the boundary is an `Omakase::Error`:

| | |
| --- | --- |
| `Omakase::ContractError` | the answer did not match the declared return type, twice |
| `Omakase::ProviderError` | the provider failed — rate limit, overload, bad key — after RubyLLM's retries |

Inside a `:code_act` loop neither reaches you: a contract miss and a raised exception both come back
to the model as an observation, and it tries again within its call budget.

## How it works

Calling a generation method does four things:

1. **Builds a request.** `Request` carries the agent, the generation (prompt, schema, strategy), the
   keyword arguments, and a fresh chat — one conversation per call, no accumulated history.
2. **Renders the prompt.** The agent's `instructions` are the system prompt; the method's prompt and
   its arguments are the user message.
3. **Runs the strategy** (below), which is where the LLM work happens.
4. **Holds it to the contract.** Whether the answer arrived as JSON or as a Ruby value from
   `finish`, it is symbolized, unwrapped if it is a lone `result`, and refused if it is off-contract.

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
is `instance_eval`d on the agent, so the agent’s methods and state are the API; anything printed and
the value of the last expression come back as the observation, and the loop repeats until the model
calls `finish(value)`. `Capabilities` lists the agent’s own methods (with their `describe` text) in
the system prompt, minus the method being written, so it cannot recurse into itself. A failure comes
back with the line that raised, `doc(object)` prints what an object of an unfamiliar type offers, and
an answer that misses the contract is rejected into the same loop — the model corrects itself without
another request. Nothing in the provider bounds a tool loop, so the tool does: ten calls, then a turn
to answer with what it has.

Because the answer is computed rather than retyped, the return type can be a Ruby class and the
method hands back the object itself:

```ruby
generates :file_ticket, "File a ticket for the message.", returns: Ticket
# => #<struct Ticket id="A-1", severity="high">
```

That needs `:code_act` — `:predict` has no code in which to build one. If the model never calls
`finish`, the strategy falls back to a tool-free turn under the JSON schema.

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
    lib/omakase/schema.rb          return types the provider enforces
    lib/omakase/type.rb            return types that are a Ruby class
    lib/omakase/capabilities.rb    the agent’s own methods, listed for the model
    lib/omakase/doc.rb             what an unfamiliar object offers, for generated code
    lib/omakase/executor.rb        runs generated Ruby against the agent
    lib/omakase/tools/ruby.rb      that executor, as a RubyLLM tool, with a call budget
    lib/omakase/fake_chat.rb       the stand-in chat for tests
    lib/omakase/strategies/        code_act, predict

## Examples

Copy `.env.example` to `.env` and fill in a key; `MODEL` and `PROVIDER` there pick the backend.

| File | Shows |
| --- | --- |
| [`feedback_agent.rb`](examples/feedback_agent.rb) | structured output in one call |
| [`inventory_agent.rb`](examples/inventory_agent.rb) | the agent's methods as the model's tools |
| [`warehouse_agent.rb`](examples/warehouse_agent.rb) | inspecting objects whose types are unknown |
| [`support_agent.rb`](examples/support_agent.rb) | plain Ruby orchestrating generated methods |
| [`support_job.rb`](examples/support_job.rb) | generation off the request thread, via ActiveJob |
| [`rails_app.rb`](examples/rails_app.rb) | a whole Rails app in one file: initializer, agent, controller |

```bash
bundle exec rake                     # tests, no network
ruby examples/inventory_agent.rb
```

## Safety

Generated code runs with `instance_eval` in your process. In a Rails app that means it can reach
`ActiveRecord`, `ENV`, and the filesystem — a container does not help, because your app is inside it
too. Two rules follow:

- **Untrusted input (anything a user typed) belongs to `:predict`.** No code runs there.
- **`:code_act` is for work you control** — internal tooling, workers, isolated environments.

What is bounded: ten tool calls per generation, a 30-second timeout per execution, and 4KB of
observation. What is not: what the code can reach. For real isolation, swap the executor —
anything answering `call(agent, code, timeout:)` will do:

```ruby
Omakase.executor = MySubprocessExecutor    # returns an observation String or Executor::Answer
```

## Roadmap

What is not here yet, roughly in the order it would earn its place:

- [x] **Live objects** — the answer is computed in code and handed back as the object, not retyped
      as JSON. Done: `finish(value)` plus `returns: SomeClass`.
- [x] **Tracing** — RubyLLM emits `chat.ruby_llm` and `tool_call.ruby_llm`; point `config.instrumenter`
      at `ActiveSupport::Notifications` and subscribe. Done, by not writing it.
- [ ] **Conversation history** — the chat is fresh per call. Keeping one per agent would let a
      method continue where the last one left off, at the cost of deciding what to keep.
- [ ] **Session storage** — persist that history and the agent state so a run can be resumed.
- [ ] **MCP tools** — external tools over the Model Context Protocol, via `ruby_llm-mcp`. Cheap to
      add, since generated code can call anything the agent exposes.
- [ ] **Skills** — capabilities as markdown files with front matter, loaded on demand rather than
      all sitting in the system prompt.
- [ ] **Memory** — recall that survives across sessions, backed by vector search.
- [x] **Concurrency** — parallel generation calls. Done: output is buffered per thread instead of
      through `$stdout`, so threads no longer collide.
