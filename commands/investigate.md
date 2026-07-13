---
description: Ask reasonix to investigate and return a read-only digest with file:line pointers.
argument-hint: "<question>"
allowed-tools: Agent, Bash, Read, Grep, Glob
---

Spawn the `reasonix-rescue` subagent and pass it the following question exactly as written:

$ARGUMENTS

Framing: read-only investigation only. Return a digest with file:line pointers; make no edits. The subagent will choose an appropriate tier, delegate to reasonix, and return only a compact digest plus a cache-hit footer. Do not perform the investigation inline in this conversation.
