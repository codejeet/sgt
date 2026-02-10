#!/usr/bin/env bash
# test_mayor_wake_dedupe_ttl.sh — Regression checks for mayor wake-trigger TTL dedupe.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _mayor_wake_dedupe_ttl_secs)"
eval "$(extract_fn _wake_trigger_key)"
eval "$(extract_fn _wake_trigger_should_suppress)"

# Config parsing sanity.
SGT_MAYOR_WAKE_DEDUPE_TTL=19
if [[ "$(_mayor_wake_dedupe_ttl_secs)" != "19" ]]; then
  echo "expected configured wake dedupe TTL to be used" >&2
  exit 1
fi
SGT_MAYOR_WAKE_DEDUPE_TTL=bad
if [[ "$(_mayor_wake_dedupe_ttl_secs)" != "15" ]]; then
  echo "expected invalid wake dedupe TTL to fall back to 15" >&2
  exit 1
fi

# Dedupe window boundary: age < ttl suppresses; age == ttl passes.
if ! _wake_trigger_should_suppress 100 114 15; then
  echo "expected age 14s to suppress within 15s ttl" >&2
  exit 1
fi
if _wake_trigger_should_suppress 100 115 15; then
  echo "expected age 15s boundary to pass through" >&2
  exit 1
fi

# Distinct keys pass through even during TTL window.
declare -A seen=()
ttl=15
now=200

a='merged:pr#77:#40:rig-a|repo=org/repo|title=A'
b='merged:pr#78:#40:rig-a|repo=org/repo|title=B'
a_replay='merged:pr#77:#40:rig-a|repo=org/repo|title=A updated'

process_event() {
  local reason="$1"
  local key last=""
  key="$(_wake_trigger_key "$reason")"
  if [[ -n "$key" ]]; then
    last="${seen[$key]:-}"
  fi
  if [[ -n "$key" ]] && _wake_trigger_should_suppress "$last" "$now" "$ttl"; then
    return 1
  fi
  if [[ -n "$key" ]]; then
    seen["$key"]="$now"
  fi
  return 0
}

if ! process_event "$a"; then
  echo "expected first key to pass" >&2
  exit 1
fi
if ! process_event "$b"; then
  echo "expected distinct key to pass" >&2
  exit 1
fi
if process_event "$a_replay"; then
  echo "expected same key replay to be suppressed" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
