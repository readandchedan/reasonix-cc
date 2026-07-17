#!/usr/bin/env bash
# Offline tests for reasonix-delegate.sh and the plugin manifest.
#
# No network or DEEPSEEK_API_KEY is required: a stub `reasonix` (tests/stub/reasonix)
# is placed first on PATH and records how the wrapper invoked it, so the tests
# assert on argv/stdin instead of calling the real CLI.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WRAPPER="$REPO/scripts/reasonix-delegate.sh"
MANIFEST="$REPO/.claude-plugin/plugin.json"

export PATH="$HERE/stub:$PATH"
chmod +x "$HERE/stub/reasonix" "$WRAPPER" 2>/dev/null || true

fail=0
check() { # <description> <command...>
  local desc="$1"; shift
  if "$@"; then
    printf 'ok   - %s\n' "$desc"
  else
    printf 'FAIL - %s\n' "$desc"
    fail=1
  fi
}

# --- tier mapping ---------------------------------------------------------
LOG="$(mktemp)"; export REASONIX_STUB_LOG="$LOG"
"$WRAPPER" --model flash "rename foo to bar" >/dev/null 2>&1 || true
check "flash tier maps to deepseek-flash provider" grep -q 'deepseek-flash' "$LOG"

LOG="$(mktemp)"; export REASONIX_STUB_LOG="$LOG"
"$WRAPPER" --model pro "add unit tests" >/dev/null 2>&1 || true
check "pro tier maps to deepseek-pro provider" grep -q 'deepseek-pro' "$LOG"

# --- regression: task must reach reasonix exactly once when context is piped
LOG="$(mktemp)"; export REASONIX_STUB_LOG="$LOG"
printf 'some gathered context\n' | "$WRAPPER" --model flash "UNIQUE_TASK_MARKER" >/dev/null 2>&1 || true
n="$(grep -c 'UNIQUE_TASK_MARKER' "$LOG" || true)"
check "task appears exactly once with stdin context (got ${n})" test "$n" -eq 1
check "piped context still reaches reasonix on stdin" grep -q 'some gathered context' "$LOG"

# --- input validation -----------------------------------------------------
if "$WRAPPER" --model bogus "x" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "unknown tier exits non-zero" test "$rc" -ne 0

# --- manifest completeness: every command file is registered --------------
for f in "$REPO"/commands/*.md; do
  base="$(basename "$f")"
  check "manifest registers commands/${base}" grep -q "commands/${base}" "$MANIFEST"
done

if [[ "$fail" -eq 0 ]]; then
  printf '\nAll tests passed.\n'
else
  printf '\nSome tests FAILED.\n'
fi
exit "$fail"
