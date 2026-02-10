#!/usr/bin/env bash
# test_mayor_snapshot_freshness_guard.sh — Regression checks for mayor snapshot stale-vs-live precedence.

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

eval "$(extract_fn _mayor_snapshot_resolve_counts)"
eval "$(extract_fn _mayor_merge_queue_revalidate_once)"

LIVE_CALLS_FILE="$(mktemp)"
_mayor_merge_queue_count() {
  echo "1" >> "$LIVE_CALLS_FILE"
  echo "$MOCK_LIVE"
}

assert_resolution() {
  local stale="$1" live="$2" expected="$3"
  MOCK_LIVE="$live"
  : > "$LIVE_CALLS_FILE"
  local got
  got="$(_mayor_merge_queue_revalidate_once "$stale")"
  if [[ "$got" != "$expected" ]]; then
    echo "unexpected resolution for stale=$stale live=$live" >&2
    echo "expected: $expected" >&2
    echo "got:      $got" >&2
    exit 1
  fi
  local live_calls
  live_calls=$(wc -l < "$LIVE_CALLS_FILE" | tr -d ' ')
  if [[ "$live_calls" -ne 1 ]]; then
    echo "expected exactly one live revalidation call, got $live_calls" >&2
    exit 1
  fi
}

# stale=1/live=0 => prefer live and mark stale snapshot.
assert_resolution "1" "0" "1|0|0|live|stale-snapshot"

# stale=0/live=1 => prefer live and surface active issue.
assert_resolution "0" "1" "0|1|1|live|stale-snapshot"

# in-sync => snapshot remains source of truth.
assert_resolution "2" "2" "2|2|2|snapshot|in-sync"

rm -f "$LIVE_CALLS_FILE"
BASH

if ! grep -q '\[mayor\] snapshot guard \$mq_guard_line' "$SGT_SCRIPT"; then
  echo "expected explicit mayor snapshot guard status line in output path" >&2
  exit 1
fi
if ! grep -q 'mq_guard_line="merge_queue_count snapshot=\$mq_snapshot_count live=\$mq_live_count chosen=\$mq_count source=\$mq_source status=\$mq_status"' "$SGT_SCRIPT"; then
  echo "expected snapshot guard line to include snapshot/live/chosen/source/status values" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
