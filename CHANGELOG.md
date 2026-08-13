# Changelog

One entry per released version, written when the gem is pushed. Until `1.0`, a minor version may
move the API — what breaks is listed first, so an upgrade is a decision rather than a surprise.

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
