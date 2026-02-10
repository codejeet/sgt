#!/usr/bin/env bash
# test_mayor_wake_replay_regression.sh - Regression checks for mayor wake replay and duplicate suppression.

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

echo "=== mayor merged wake replay coalescing ==="
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

eval "$(extract_fn _dedupe_wake_reasons)"
eval "$(extract_fn _wake_requires_dispatch_decision)"

merged='merged:pr#77:#40:rig-a|repo=org/repo|title=Fix flaky CI|pr_url=https://github.com/org/repo/pull/77|issue_url=https://github.com/org/repo/issues/40'
orphan='orphan-pr:#22:rig-a'

mapfile -t deduped < <(_dedupe_wake_reasons "$merged" "$merged" "$orphan" "$merged")
if [[ "${#deduped[@]}" -ne 2 ]]; then
  echo "expected 2 coalesced events, got ${#deduped[@]}" >&2
  exit 1
fi

if [[ "${deduped[0]}" != "$merged" || "${deduped[1]}" != "$orphan" ]]; then
  echo "unexpected coalesced ordering/content" >&2
  exit 1
fi

dispatch_decisions=0
for reason in "${deduped[@]}"; do
  if _wake_requires_dispatch_decision "$reason"; then
    dispatch_decisions=$((dispatch_decisions + 1))
  fi
done

if [[ "$dispatch_decisions" -ne 1 ]]; then
  echo "expected exactly one dispatch decision for replayed merged wake events, got $dispatch_decisions" >&2
  exit 1
fi
BASH

echo "=== mayor wake trigger ttl dedupe ==="
"$REPO_ROOT/test_mayor_wake_dedupe_ttl.sh"

echo "=== mayor post-merge dispatch durable dedupe fence ==="
"$REPO_ROOT/test_mayor_post_merge_dispatch_fence.sh"

echo "=== mayor cycle lease lock recovery ==="
"$REPO_ROOT/test_mayor_cycle_lock_lease.sh"

echo "=== duplicate sling suppression during cooldown ==="
"$REPO_ROOT/test_mayor_dispatch_idempotency.sh"

echo "=== stale snapshot dispatch race guard ==="
"$REPO_ROOT/test_mayor_stale_dispatch_race.sh"

echo "=== mayor snapshot freshness guard ==="
"$REPO_ROOT/test_mayor_snapshot_freshness_guard.sh"

echo "=== mayor orphan stale snapshot guard ==="
"$REPO_ROOT/test_mayor_orphan_stale_snapshot_guard.sh"

echo "=== mayor critical alert cooldown dedupe ==="
"$REPO_ROOT/test_mayor_critical_alert_cooldown.sh"

echo "=== mayor stalled refinery REVIEW_UNCLEAR watchdog ==="
"$REPO_ROOT/test_mayor_review_watchdog.sh"

echo "=== mayor decision log durability ==="
"$REPO_ROOT/test_mayor_decision_log_durability.sh"

echo "=== mayor merge-queue alias dedupe ==="
"$REPO_ROOT/test_mayor_merge_queue_alias_dedupe.sh"

echo "=== refinery stale queue item guard ==="
"$REPO_ROOT/test_refinery_stale_queue_item.sh"

echo "=== refinery stale post-merge redispatch guard ==="
"$REPO_ROOT/test_refinery_stale_post_merge_redispatch.sh"

echo "=== refinery duplicate PR-ready replay dedupe ==="
"$REPO_ROOT/test_refinery_pr_ready_dedupe.sh"

echo "=== refinery restart replay merge-attempt dedupe ==="
"$REPO_ROOT/test_refinery_merge_attempt_restart_replay.sh"

echo "ALL TESTS PASSED"
