# Changelog

One entry per released version, written when the gem is pushed. Until `1.0`, a minor version may
move the API — what breaks is listed first, so an upgrade is a decision rather than a surprise.

## 0.3.0

One thing changes under you: a generation may no longer call itself. The rest is additions — a real
signature for the inputs, a trace to read a run by, a seam for the chat, and your own validations
enforced on the way out.

### Breaking

- A generation may not re-enter itself. While `SupportAgent#reply` is running on an object, that
  object's `reply` raises `Omakase::Error` instead of opening a second run. Generated code can see
  the method and call it, and each nested call opened its own chat with its own tool budget — so the
  budget bounded nothing. A *fresh* agent may still recurse: that is the sub-agents pattern, one
  object per node of a tree, and the tree is the thing that ends.

### Added

- `takes:` names the keyword arguments, and then Ruby checks them:
  `generates :translate, takes: %i[text language]`. A missing or misspelled argument is an
  `ArgumentError` at the call rather than noise in a prompt, and the model reads the names instead
  of `**inputs`. `with:` stays available for attachments. Anything that is not a plain keyword name
  is refused where it is declared.
- `Omakase::Trace` — the listener printed for a human: `Omakase.listener = Omakase::Trace.new`. A run
  reads top to bottom: the call, the code the model wrote, the answer. Colour when the stream is a
  terminal, plain when it is a log.
- `Omakase.chat_factory` — how an agent gets a chat when none was injected. One line in
  `test_helper.rb` keeps a whole suite off the network, including the class-level calls a job makes,
  which have no seam to inject through. Anything answering `call(**options)` will do, and an
  injected `chat:` still wins.
- A `returns:` class that answers `valid?` and `errors` — which is every ActiveModel — is asked
  before the answer is handed back, and an invalid one is refused. Under `:code_act` the refusal
  reaches the model as `finish rejected: Post is invalid: …`, and it corrects itself inside the same
  loop. Your validations are the contract, and they stay where you wrote them.
- `doc(object)` takes a class as well as an instance: what an object of that type would offer, plus
  the column names when it is a record. The model asks before it builds a type it has only been told
  the name of.

### Fixed

- What generated code printed before `finish` is no longer lost — `Executor::Answer` carries it, so a
  trace shows the working and not only the answer. `printed:` defaults, so a replacement executor
  that knows the value alone still satisfies the seam.

## 0.2.0

Nothing breaks. Four additions, each one a keyword or a seam that costs nothing when unused.

### Added

- A prompt can be a block: `generates :translate, -> { "Translate to #{@language}." }`. It is read
  at call time, on the agent, so one declaration serves an object however it is configured. A prompt
  that is neither a String nor a block is refused where it is declared. In the capability list a
  block-prompted method shows its signature alone — `describe` it to say more.
- `generates :classify, model: "claude-haiku-4-5"` — a generation method can name its own model, a
  cheap one beside a strong one. The id lands on top of the class's chat options, so the provider
  stays the class's; an injected `chat:` still wins.
- `Omakase.listener` — one callback for every step as it happens: `:generation` (`agent:, name:,
  inputs:`), `:ruby` (`agent:, code:, outcome:`), `:answer` (`agent:, name:, value:`). Anything
  answering `call(event, **payload)` will do; nil, the default, costs nothing.
- `with:` is a reserved argument: it is not rendered into the prompt but passed to RubyLLM's
  `ask(with:)` as attachments — images, audio, PDFs, as paths, URLs or IO. `FakeChat` records them.

## 0.1.0

First stable release. `0.0.x` was a prerelease and needed `gem install --pre`; this does not.

### Breaking

- `:code_act` with a Ruby class return type (`returns: SomeClass`) no longer falls back to
  `:predict` when the model does not call `finish`. It could not have worked — a class cannot be
  expressed as a JSON schema — and the fallback raised `returns: X needs the :code_act strategy`
  from inside the wrong strategy. It now raises `ContractError` naming the method and the shape it
  never returned. Schemas declared with a block or a scalar still fall back as before.
- `doc(object)` stops at `ActiveRecord::Base` and prints a record's columns as state rather than as
  methods. Output for an `ActiveRecord` object goes from several hundred lines of framework
  internals to its associations, your methods, and the values it holds.
- The prompt asks for `finish(Refund.new(order_id:, amount:, reason:))` where it used to say
  `finish(a Refund)`, for any return type that answers `members` (a `Struct` or a `Data`).

### Added

- `mcp` — an MCP server's tools become methods on the agent, via `ruby_llm-mcp` (an optional
  dependency; `require` it and options pass through verbatim).
- `skill` — a `SKILL.md` directory becomes one described method: the front matter's description
  joins the agent's capabilities, the body arrives only when the model calls it.
- `memory` — `remember(text)` and `recall(query)` over RubyLLM embeddings, with the store as a
  field, so it marshals with the agent.
- `context` — an instance method to override; whatever it returns is appended to the class's
  instructions on every call. The chat stays fresh per call, deliberately.
- `Marshal.dump(agent)` is the session: an agent marshals like any object, minus its live chat.

## 0.0.2.alpha, 0.0.1.alpha

Prereleases. `Agent`, `generates`, `describe`, the `:predict` and `:code_act` strategies,
`finish(value)`, `returns: SomeClass`, `doc`, per-thread output, `FakeChat`, and the Rails notes.
