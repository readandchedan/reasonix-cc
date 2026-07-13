# reasonix-cc

A Claude Code plugin that delegates coarse, well-specified, easy-to-verify, high-volume tasks to DeepSeek via the [`reasonix`](https://github.com/esengine/deepseek-reasonix) CLI. Claude stays the orchestrator and verifier; reasonix does the bulk labor (wide file-reading, mechanical edits, log triage, test scaffolding) at a fraction of the token cost.

Use it when the work is decomposable, verifiable by a test/typecheck/grep, and heavy enough that doing it inline in Claude would burn a lot of context. Keep architecture, ambiguous requirements, and anything where verifying ≈ re-deriving on Claude.

## Install

1. Clone or copy this plugin into your Claude Code plugins directory and enable it.
2. Install `reasonix` and run the setup wizard:
   ```bash
   # install reasonix (see github.com/esengine/deepseek-reasonix)
   reasonix setup          # creates ./reasonix.toml
   ```
3. Set your API key. Either export `DEEPSEEK_API_KEY` or let reasonix manage it in its home `.env`.
4. Run `/reasonix:init` in Claude Code to verify `reasonix.toml` and `AGENTS.md` are present.

## Tier-routing table

| Tier | Use for | Who verifies |
|------|---------|--------------|
| **Flash** (`/reasonix:delegate --model flash`) | Mechanical, high-volume, simple work: codemods, boilerplate, log triage, simple test scaffolds. | Claude |
| **Pro** (`/reasonix:delegate --model pro`) | Reasoning-heavier delegated work: investigation synthesis, non-trivial implementation. | Claude |
| **Opus / Claude** | Orchestration, verification, architecture, ambiguous requirements — never delegated. | — |

## The delegation rule

> Only delegate work that is **(a)** decomposable, **(b)** cheaply verifiable by Claude — a passing test, a typecheck, a grep-checkable map — and **(c)** tonnage-heavy. Keep architecture, ambiguous requirements, and anything where verifying ≈ re-deriving on Claude.

## Cache note

`reasonix` benefits from DeepSeek's server-side prefix cache. The frozen prefix is built from `AGENTS.md` plus the tool specifications, so keep `AGENTS.md` byte-stable. Delegations that are bursty (within the cache TTL) stay cheap because repeated one-shot `reasonix run` calls reuse the same cached prefix.

Run `scripts/cache-smoke-test.sh` to confirm cache warmth on your machine. It executes the same trivial call twice and compares the reported `cache_hit_tokens` / `cache_miss_tokens`; a warm cache shows call-2 with a high cache-hit fraction.

## Commands

- `/reasonix:delegate <task>` — hand a coarse, verifiable task to reasonix and return a digest.
- `/reasonix:investigate <question>` — read-only investigation; returns a digest with file:line pointers.
- `/reasonix:init` — verify `reasonix.toml` and `AGENTS.md` are present; guide the user through setup if not.

## License

MIT
