#!/usr/bin/env bash
# reasonix-delegate.sh — thin wrapper around `reasonix run` for Claude Code plugin use.
# Usage: reasonix-delegate.sh --model <pro|flash> [--plan-mode] [--max-steps N]
#        [--verify-cmd "<cmd>"] [--context-file <path>] [--metrics-file <path>] "<task string>"
# Context may also be piped via stdin.
#
# Verified against `reasonix run --help` (reasonix v1.17.10):
#   --model NAME    provider name (default: config default_model)
#   --metrics PATH  write a JSON token/cache/cost summary of the run to this path
#   --max-steps N   max agentic iterations before forced text-only response
# Provider names verified via `reasonix doctor --json`: deepseek-pro, deepseek-flash.
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: reasonix-delegate.sh --model <pro|flash> [--plan-mode] [--max-steps N]
       [--verify-cmd "<cmd>"] [--context-file <path>] [--metrics-file <path>] "<task string>"
EOF
}

# Plan-following rules prepended to the task when --plan-mode is set.
# Addresses "understand-then-regenerate" failures: when a plan contains verbatim
# code blocks, reasonix must transcribe them, not reinterpret them.
plan_rules() {
  cat <<'RULES'
## Plan-following rules (mandatory)

You are implementing from a plan document that contains complete code blocks.
Follow these rules strictly:

1. **Verbatim transcription.** When the plan contains a fenced code block that
   is a complete implementation (not pseudocode, not a "do something like this"
   example), insert it verbatim. Do not rename variables, reorder columns,
   substitute identifiers, or "improve" the code. If you believe the plan's
   code has a bug, note it in a comment but still use the plan's code as the
   base. This applies especially to:
   - SQL DDL (CREATE TABLE, PRIMARY KEY, ON CONFLICT)
   - Dataclass / struct definitions (every field name is a contract)
   - Function signatures with exact parameter names
   - Test assertions with expected values

2. **Cross-file contract tracking.** When a dataclass/struct/model is defined
   in the plan, treat its field list as a contract. Every file that handles
   that model — the parser, the storage layer, the tests — must reference
   every field by the exact name from the definition. Before declaring done,
   enumerate every field and verify the parser extracts it, the storage INSERT
   lists it, and at least one test asserts on it.

3. **Anchor tests from the plan.** Write tests that assert on values from
   the plan's own test code blocks (verbatim). Do not invent your own expected
   values that differ from the plan. If the plan says `assert r.event_id ==
   "3242"`, your test must say `assert r.event_id == "3242"` — not `"3241"`
   or any other value you derived.

4. **Phased execution.** For tasks touching more than 5 files, execute in
   phases: (1) foundation (constants, models), (2) data layer (client,
   extract, cache, storage), (3) pipeline (crawl, etl), (4) CLI + scripts +
   tests. After each phase, run the verification command and re-read the
   plan's code blocks for that phase. Do not proceed until the current
   phase passes.

5. **After writing each file**, re-read the plan's code blocks for that file
   and diff them against what you wrote. If any identifier, column name, or
   constant differs, fix it immediately.

---

RULES
}

main() {
  local tier="pro"
  local context_file=""
  local metrics_file=""
  local max_steps=""
  local verify_cmd=""
  local plan_mode=false
  local task=""

  # Parse arguments.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model)
        tier="${2:-}"
        if [[ -z "$tier" ]]; then
          usage
          exit 2
        fi
        shift 2
        ;;
      --context-file)
        context_file="${2:-}"
        if [[ -z "$context_file" ]]; then
          usage
          exit 2
        fi
        shift 2
        ;;
      --metrics-file)
        metrics_file="${2:-}"
        if [[ -z "$metrics_file" ]]; then
          usage
          exit 2
        fi
        shift 2
        ;;
      --max-steps)
        max_steps="${2:-}"
        if [[ -z "$max_steps" ]]; then
          usage
          exit 2
        fi
        shift 2
        ;;
      --verify-cmd)
        verify_cmd="${2:-}"
        if [[ -z "$verify_cmd" ]]; then
          usage
          exit 2
        fi
        shift 2
        ;;
      --plan-mode)
        plan_mode=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        exit 2
        ;;
      *)
        break
        ;;
    esac
  done

  # Remaining positional argument is the task string.
  if [[ $# -gt 0 ]]; then
    task="$*"
  fi

  # Build context from optional file and/or stdin.
  local context=""
  if [[ -n "$context_file" ]]; then
    if [[ ! -f "$context_file" ]]; then
      printf 'Error: context-file not found: %s\n' "$context_file" >&2
      exit 2
    fi
    context="$(cat "$context_file")"
    context="${context}

"
  fi

  if [[ ! -t 0 ]]; then
    local stdin_context=""
    stdin_context="$(cat)"
    if [[ -n "$stdin_context" ]]; then
      if [[ -n "$context" ]]; then
        context="${context}${stdin_context}"
      else
        context="${stdin_context}"
      fi
    fi
  fi

  if [[ -z "$task" && -z "$context" ]]; then
    usage
    exit 2
  fi

  # Prepend plan-following rules to the task when --plan-mode is set.
  if $plan_mode; then
    task="$(plan_rules)${task}"
  fi

  # Preflight: reasonix must be installed.
  if ! command -v reasonix >/dev/null 2>&1; then
    cat <<'EOF' >&2
reasonix not found — install from github.com/esengine/deepseek-reasonix and run `reasonix setup`
EOF
    exit 3
  fi

  # Soft auth check: warn if neither env key nor reasonix home .env is present.
  local reasonix_home=""
  if [[ -n "${REASONIX_HOME:-}" ]]; then
    reasonix_home="$REASONIX_HOME"
  elif [[ -d "${HOME}/.reasonix" ]]; then
    reasonix_home="${HOME}/.reasonix"
  fi
  if [[ -z "${DEEPSEEK_API_KEY:-}" && ( -z "$reasonix_home" || ! -f "${reasonix_home}/.env" ) ]]; then
    printf 'Warning: DEEPSEEK_API_KEY is unset and no reasonix home .env was detected.\n' >&2
    printf 'reasonix may still use its own key management, but delegation could fail.\n' >&2
  fi

  # Map tier to reasonix provider name.
  # Verified provider names: deepseek-pro -> deepseek-v4-pro, deepseek-flash -> deepseek-v4-flash.
  local model_id=""
  case "$tier" in
    pro)
      model_id="deepseek-pro"
      ;;
    flash)
      model_id="deepseek-flash"
      ;;
    *)
      printf 'Error: unknown tier "%s". Use "pro" or "flash".\n' "$tier" >&2
      exit 2
      ;;
  esac

  # Build the reasonix run command array (always non-empty, so set -u is safe).
  # --metrics verified: writes JSON with prompt_tokens, cache_hit_tokens, cache_miss_tokens, cost.
  local reasonix_cmd=(reasonix run --model "$model_id")
  if [[ -n "$metrics_file" ]]; then
    reasonix_cmd+=(--metrics "$metrics_file")
  fi
  if [[ -n "$max_steps" ]]; then
    reasonix_cmd+=(--max-steps "$max_steps")
  fi
  reasonix_cmd+=("$task")

  # Invoke reasonix, piping context via stdin when present.
  local rc=0
  if [[ -n "$context" ]]; then
    # Prepend context to the task so reasonix receives it on stdin.
    printf '%s\n\n%s\n' "$context" "$task" | "${reasonix_cmd[@]}" || rc=$?
  else
    "${reasonix_cmd[@]}" || rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    printf 'reasonix run exited with code %d\n' "$rc" >&2
    exit "$rc"
  fi

  # File-change manifest (only if inside a git work tree).
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '\n=== File changes ===\n'
    git diff --stat 2>/dev/null || true
    git status --short 2>/dev/null || true
  fi

  # Optional verification command.
  if [[ -n "$verify_cmd" ]]; then
    printf '\n=== Verification ===\n'
    local vrc=0
    bash -c "$verify_cmd" || vrc=$?
    if [[ $vrc -eq 0 ]]; then
      printf '\n[verify: PASS]\n'
    else
      printf '\n[verify: FAIL — exit %d]\n' "$vrc"
    fi
  fi
}

main "$@"
