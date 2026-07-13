---
description: Verify reasonix setup and AGENTS.md are in place.
argument-hint: ""
allowed-tools: Bash, Glob, Read
---

Check the current workspace for `reasonix.toml` and `AGENTS.md`.

- If `reasonix.toml` is missing, tell the user to run `reasonix setup` first.
- If `AGENTS.md` is missing, tell the user to run `reasonix` interactively and then `/init` to generate it.
- If both are present, confirm the plugin is ready to delegate.

Emphasize that `AGENTS.md` is the frozen cache prefix for DeepSeek's server-side prefix cache. Keep it byte-stable; do not edit it casually. Delegations that land within the cache TTL stay cheap because the frozen prefix is reused across one-shot `reasonix run` calls.
