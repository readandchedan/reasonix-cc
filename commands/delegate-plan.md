---
description: Delegate a plan-driven implementation task to reasonix with verbatim-transcription guards.
argument-hint: "<task>"
allowed-tools: Agent, Bash, Read, Grep, Glob
---

Spawn the `reasonix-rescue` subagent and pass it the following task exactly as written:

$ARGUMENTS

Framing: plan-driven implementation. The task references a plan document (markdown file) that contains step-by-step instructions with verbatim code blocks. Delegate to reasonix with `--plan-mode` (which prepends plan-following rules: verbatim transcription, cross-file contract tracking, anchor tests, phased execution, post-write diff) and return the digest plus the file-change manifest. Do not perform the work inline in this conversation.
