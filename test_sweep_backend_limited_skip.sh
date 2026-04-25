#!/usr/bin/env bash
# test_sweep_backend_limited_skip.sh — Sweep watchdog must not re-sling issues marked backend-limited.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _issue_has_label)"
eval "$(extract_fn _issue_backend_dispatch_limited_reason)"
eval "$(extract_fn _sweep_watchdog_resling_open_authorized_issues)"

export SGT_LOG="$TMP_ROOT/sgt.log"
RESLING_FILE="$TMP_ROOT/resling-calls"
GH_CALLS_FILE="$TMP_ROOT/gh-calls"
: > "$RESLING_FILE"
: > "$GH_CALLS_FILE"

log_event() {
  printf '%s\n' "${1:-}" >> "$SGT_LOG"
}

_mayor_rig_manually_hibernated() { return 1; }
_repo_owner_repo() { printf '%s\n' "${1#https://github.com/}"; }
_escape_quotes() { printf '%s' "$1"; }
_gh_issue_labels_live() {
  gh issue view "$2" --repo "$1" --json labels --jq '.labels[].name'
}
_resling_find_existing_issue_polecat() { return 1; }
_sweep_watchdog_find_open_pr_for_issue() { return 1; }
_ai_backend_default() { echo "codex"; }
_resling_existing_issue() {
  printf '%s\n' "$*" >> "$RESLING_FILE"
  return 0
}

gh() {
  local args=" $* "
  printf '%s\n' "$args" >> "$GH_CALLS_FILE"
  if [[ "$args" == *" issue list "* ]]; then
    printf '177\tBlocked issue title\n'
    return 0
  fi
  if [[ "$args" == *" issue view "* && "$args" == *" --json labels "* ]]; then
    printf 'backend-limited\n'
    return 0
  fi
  echo "mock gh unsupported: $*" >&2
  return 1
}

_sweep_watchdog_resling_open_authorized_issues "rig-one" "https://github.com/acme/demo"

if [[ -s "$RESLING_FILE" ]]; then
  echo "expected backend-limited issue to skip sweep watchdog re-sling" >&2
  cat "$RESLING_FILE" >&2
  exit 1
fi
grep -q 'SWEEP_WATCHDOG_RESLING_SKIP issue=#177 rig=rig-one repo=acme/demo reason_code=backend_usage_limit' "$SGT_LOG"

echo "ALL TESTS PASSED"
