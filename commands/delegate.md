---
description: Delegate a coarse, verifiable, high-volume task to reasonix and return a digest.
argument-hint: "<task>"
allowed-tools: Agent, Bash, Read, Grep, Glob
---

Spawn the `reasonix-rescue` subagent and pass it the following task exactly as written:

$ARGUMENTS

Framing: implement/produce. The subagent will choose an appropriate tier, delegate to reasonix, and return only a compact digest plus a cache-hit footer. Do not perform the work inline in this conversation.
