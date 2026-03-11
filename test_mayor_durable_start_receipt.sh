#!/usr/bin/env bash
# test_mayor_durable_start_receipt.sh — Mayor must not emit a startup receipt before the loop is durably live.

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

echo "=== mayor does not write startup receipt when lock claim is blocked ==="
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

eval "$(extract_fn _mayor_start_receipt_file)"
eval "$(extract_fn _mayor_start_receipt_write)"
eval "$(extract_fn _mayor_loop)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_MAYOR_FIFO="$SGT_CONFIG/mayor.fifo"
SGT_MAYOR_INTERVAL="600"
EVENT_LOG="$TMP_ROOT/events.log"
mkdir -p "$SGT_CONFIG"
export SGT_ROOT SGT_CONFIG SGT_MAYOR_FIFO SGT_MAYOR_INTERVAL EVENT_LOG

_mayor_lock_claim() {
  printf 'blocked-live|777|100|200|owner-live-with-valid-lease\n'
  return 1
}

log_event() {
  printf '%s\n' "$*" >> "$EVENT_LOG"
}

set +e
_mayor_loop > "$TMP_ROOT/mayor.out" 2>&1
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  echo "expected blocked lock path to return cleanly" >&2
  exit 1
fi
if [[ -f "$SGT_CONFIG/mayor-start.receipt" ]]; then
  echo "expected no mayor startup receipt when lock claim is blocked" >&2
  cat "$SGT_CONFIG/mayor-start.receipt" >&2
  exit 1
fi
if [[ -s "$EVENT_LOG" ]] && grep -q 'MAYOR_START' "$EVENT_LOG"; then
  echo "expected blocked lock path to avoid MAYOR_START telemetry" >&2
  cat "$EVENT_LOG" >&2
  exit 1
fi
if ! grep -q 'lock decision: blocked-live' "$TMP_ROOT/mayor.out"; then
  echo "expected blocked lock decision to remain operator-visible" >&2
  cat "$TMP_ROOT/mayor.out" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
