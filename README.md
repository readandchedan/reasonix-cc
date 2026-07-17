# reasonix-cc

A Claude Code plugin that lets Claude delegate implementation work to DeepSeek via the [`reasonix`](https://github.com/esengine/deepseek-reasonix) CLI, using its own judgement about when to hand off. Claude stays the orchestrator and verifier; reasonix does the bulk labor (wide file-reading, mechanical edits, log triage, test scaffolding) at a fraction of the token cost.

Claude uses its own judgement to decide whether to delegate — it does not need an explicit `/reasonix:delegate` command or the user's permission. Hand off implementation/coding work (especially mechanical, high-volume, or verifiable-after-the-fact tasks) to the `reasonix-rescue` subagent; keep architecture, ambiguous requirements, and anything where verifying ≈ re-deriving in the main loop.

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
| **Flash** (`--model flash`) | Trivial/mechanical work: codemods, renames, boilerplate, log triage, simple test scaffolds, wide file reading. ≈3× cheaper than Pro. | Claude |
| **Pro** (`--model pro`) | Substantive implementation: non-trivial features from a spec, investigation synthesis, anything with ambiguity. Roughly Haiku-vs-Sonnet — use when Flash would likely misread the task. | Claude |
| **Opus / Claude** | Judgement, orchestration, verification, architecture, ambiguous requirements — stays in the main loop. | — |

## How delegation gets triggered

Claude decides on its own — inspired by [Simon Willison's "use your judgement" note](https://simonwillison.net/2026/jul/3/judgement/) and the Claude Code team's tip: tell the model to use its own judgement about when to delegate to a lower-power model, rather than dictating a rigid rule. The `reasonix-rescue` subagent's description advertises itself for "implementation/coding tasks the primary agent judges cheaper to execute on DeepSeek", so Claude can invoke it whenever it makes sense.

`/reasonix:delegate` and `/reasonix:investigate` stay as manual escape hatches — they force a delegation even when Claude would otherwise do the work inline. They are not the only trigger.

To make Claude delegate proactively in every project, add a judgment-based rule to your global `~/.claude/CLAUDE.md` (or project `CLAUDE.md` / `AGENTS.md`). A ready-made example:

```markdown
## Delegation to reasonix

For implementation and coding tasks, use your own judgement to decide whether to
delegate the work to reasonix (a DeepSeek-backed CLI) instead of doing it inline.
You do not need an explicit `/reasonix:delegate` command or the user's permission —
invoke the `reasonix-rescue` subagent whenever your judgement says it is the
cheaper path.

Why delegate: DeepSeek Flash via reasonix is far cheaper per token than your own
model (often an order of magnitude), and is competent at mechanical coding work
— codemods, boilerplate, test scaffolding, log triage, wide file reading. It is
weaker at reasoning-heavy or ambiguous tasks; those stay with you. The bet pays
off when the task is mostly volume and the result is cheaply verifiable afterward.

How to choose a tier (Flash ≈ 3× cheaper than Pro; Pro ≈ 10× cheaper than your model):
- Flash: trivial/mechanical — codemods, renames, boilerplate, log triage, simple
  test scaffolds, wide file reading.
- Pro: substantive implementation — non-trivial features from a spec, investigation
  synthesis, anything with ambiguity. Use when Flash would likely misread the task.
- Default to Pro when unsure; redoing a botched delegation costs more than the gap.

Worth delegating: mechanical implementation, boilerplate, test scaffolding, log
triage, wide file reading, codemods — anything where the result is cheaply
verifiable afterward (a passing test, a typecheck, a grep, a build).
Keep in the main loop: architecture, ambiguous requirements, design decisions,
data synthesis, auditing, security-sensitive changes, and anything where
verifying ≈ re-deriving.

After the digest returns, run the verification yourself and report pass/fail.
```

## Cache note

`reasonix` benefits from DeepSeek's server-side prefix cache. The frozen prefix is built from `AGENTS.md` plus the tool specifications, so keep `AGENTS.md` byte-stable. Delegations that are bursty (within the cache TTL) stay cheap because repeated one-shot `reasonix run` calls reuse the same cached prefix.

Run `scripts/cache-smoke-test.sh` to confirm cache warmth on your machine. It executes the same trivial call twice and compares the reported `cache_hit_tokens` / `cache_miss_tokens`; a warm cache shows call-2 with a high cache-hit fraction.

## Commands

- `/reasonix:delegate <task>` — hand a coarse, verifiable task to reasonix and return a digest.
- `/reasonix:delegate-plan <task>` — delegate a plan-driven implementation (markdown with verbatim code blocks) with plan-following guards: verbatim transcription, cross-file contract tracking, anchor tests, phased execution.
- `/reasonix:investigate <question>` — read-only investigation; returns a digest with file:line pointers.
- `/reasonix:init` — verify `reasonix.toml` and `AGENTS.md` are present; guide the user through setup if not.

## Delegate wrapper flags

`reasonix-delegate.sh` accepts:

| Flag | Purpose |
|------|---------|
| `--model <pro\|flash>` | DeepSeek tier (required). Flash for mechanical work, Pro for reasoning. |
| `--plan-mode` | Prepend plan-following rules (verbatim transcription, cross-file contracts, anchor tests, phased execution) to the task. Use when delegating from a plan document with code blocks. |
| `--max-steps N` | Cap reasonix's agentic iterations (passthrough to `reasonix run --max-steps`). |
| `--verify-cmd "<cmd>"` | Run a verification command (e.g. `uv run pytest`, `npm test`) after reasonix finishes; include pass/fail in the output. Saves the primary agent a round-trip. |
| `--context-file <path>` | Prepend file contents as context. |
| `--metrics-file <path>` | Write JSON token/cache/cost summary to this path. |

After reasonix returns, the wrapper automatically appends a **file-change manifest** (`git diff --stat` + `git status --short`, if inside a git repo) and the **verification result** (if `--verify-cmd` was used) to the output. The primary agent sees what changed and whether it passed in one digest.

## License

MIT
