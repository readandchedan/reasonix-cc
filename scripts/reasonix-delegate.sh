#!/usr/bin/env bash
# reasonix-delegate.sh — thin wrapper around `reasonix run` for Claude Code plugin use.
# Usage: reasonix-delegate.sh --model <pro|flash> [--context-file <path>] [--metrics-file <path>] "<task string>"
# Context may also be piped via stdin.
#
# Verified against `reasonix run --help` (reasonix v1.17.10):
#   -model string   provider name (default: config default_model)
#   -metrics string write a JSON token/cache/cost summary of the run to this path
# Provider names verified via `reasonix doctor --json`: deepseek-pro, deepseek-flash.
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: reasonix-delegate.sh --model <pro|flash> [--context-file <path>] [--metrics-file <path>] "<task string>"
EOF
}

main() {
  local tier="pro"
  local context_file=""
  local metrics_file=""
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
}

main "$@"
