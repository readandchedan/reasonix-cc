#!/usr/bin/env bash
# cache-smoke-test.sh — verify reasonix's prefix cache stays warm across two one-shot calls.
#
# Signal: reasonix --metrics JSON (cache_hit_tokens / cache_miss_tokens).
# A warm cache shows call-2 with a high cache-hit fraction and very few miss tokens.
set -euo pipefail

TASK="reply with the single word: pong"
MODEL="deepseek-pro"
METRICS1="$(mktemp)"
METRICS2="$(mktemp)"
trap 'rm -f "$METRICS1" "$METRICS2"' EXIT

preflight() {
  if ! command -v reasonix >/dev/null 2>&1; then
    cat <<'EOF' >&2
reasonix not found — install from github.com/esengine/deepseek-reasonix and run `reasonix setup`
EOF
    exit 3
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'jq not found; install jq to parse --metrics JSON.\n' >&2
    exit 3
  fi
}

run_call() {
  local n="$1"
  local metrics_path="$2"
  printf '\n=== Call %s ===\n' "$n"
  reasonix run --model "$MODEL" --metrics "$metrics_path" "$TASK"
}

extract() {
  local path="$1"
  local key="$2"
  jq -r ".${key} // \"n/a\"" "$path"
}

main() {
  preflight

  run_call 1 "$METRICS1"
  run_call 2 "$METRICS2"

  local p1 p2 h1 h2 m1 m2
  p1="$(extract "$METRICS1" prompt_tokens)"
  h1="$(extract "$METRICS1" cache_hit_tokens)"
  m1="$(extract "$METRICS1" cache_miss_tokens)"
  p2="$(extract "$METRICS2" prompt_tokens)"
  h2="$(extract "$METRICS2" cache_hit_tokens)"
  m2="$(extract "$METRICS2" cache_miss_tokens)"

  printf '\n=== Cache warmth comparison ===\n'
  printf 'Call 1 — prompt_tokens=%s cache_hit_tokens=%s cache_miss_tokens=%s\n' "$p1" "$h1" "$m1"
  printf 'Call 2 — prompt_tokens=%s cache_hit_tokens=%s cache_miss_tokens=%s\n' "$p2" "$h2" "$m2"

  if [[ "$h1" != "n/a" && "$h2" != "n/a" && "$p1" != "n/a" && "$p2" != "n/a" ]]; then
    local hit1_pct hit2_pct
    hit1_pct="$(jq -n --arg h "$h1" --arg p "$p1" '100 * ($h|tonumber) / ($p|tonumber)')"
    hit2_pct="$(jq -n --arg h "$h2" --arg p "$p2" '100 * ($h|tonumber) / ($p|tonumber)')"
    printf 'Call 1 cache-hit fraction: %.1f%%\n' "$hit1_pct"
    printf 'Call 2 cache-hit fraction: %.1f%%\n' "$hit2_pct"
    if [[ "$(jq -n --arg h2 "$hit2_pct" '($h2|tonumber) > 50')" == "true" ]]; then
      printf '\nResult: WARM — call-2 reused the majority of the prefix cache.\n'
    else
      printf '\nResult: COLD — call-2 did not show a warm cache signal.\n'
    fi
  else
    printf '\nResult: unable to compute cache-hit fraction from metrics JSON.\n'
  fi
}

main "$@"
