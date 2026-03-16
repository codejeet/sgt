#!/usr/bin/env bash
# test_notification_blind_spots.sh — Regression coverage for issue #232:
#   (1) Post-merge verification treats pr_state=MERGED + branch_deleted=true as success
#       regardless of issue_state (GitHub auto-closes issues via "Closes #N").
#   (2) cmd_sling sends _notify_openclaw after successful dispatch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# ── Test 1: Post-merge verification — MERGED + branch_deleted=true = success regardless of issue_state ──
echo "=== Test 1: post-merge verify treats MERGED+branch_deleted=true as success regardless of issue_state ==="

# The key invariant: when pr_state=MERGED and branch_deleted=true and merged_sha is valid,
# outcome must be "success" — issue_state should NOT gate this.

# Verify the first MERGED+branch_deleted=true condition does not require issue_state=OPEN
first_condition="$(grep -A1 'pr_state.*==.*MERGED.*branch_deleted.*==.*true' "$SGT_SCRIPT" | head -1 || true)"
if [[ -n "$first_condition" ]] && ! echo "$first_condition" | grep -q 'issue_state'; then
  pass "first MERGED+branch_deleted=true condition does not require issue_state=OPEN"
else
  fail "first MERGED+branch_deleted=true condition still gates on issue_state"
fi

# Verify the old pattern (requiring issue_state=OPEN alongside branch_deleted=true) is gone
if grep -q 'pr_state.*MERGED.*issue_state.*==.*OPEN.*branch_deleted.*true' "$SGT_SCRIPT"; then
  fail "old pattern requiring issue_state=OPEN with branch_deleted=true still present"
else
  pass "old issue_state=OPEN gate removed from primary success path"
fi

# ── Test 2: Integration — run the existing issue_auto_closed scenario ──
echo "=== Test 2: integration — issue_auto_closed scenario (existing test) ==="

if bash "$REPO_ROOT/test_refinery_post_merge_verification_receipt_fence.sh" >/dev/null 2>&1; then
  pass "test_refinery_post_merge_verification_receipt_fence.sh passes (includes issue_auto_closed)"
else
  fail "test_refinery_post_merge_verification_receipt_fence.sh failed"
fi

# ── Test 3: cmd_sling contains _notify_openclaw call ──
echo "=== Test 3: cmd_sling calls _notify_openclaw after dispatch ==="

# Extract cmd_sling function body
sling_body="$(sed -n '/^cmd_sling()/,/^[a-z_]*() *{/p' "$SGT_SCRIPT")"

if echo "$sling_body" | grep -q '_notify_openclaw.*SGT Sling.*dispatched'; then
  pass "cmd_sling contains _notify_openclaw call with dispatch message"
else
  fail "cmd_sling missing _notify_openclaw call"
fi

if echo "$sling_body" | grep -q '_notify_openclaw.*rig=.*issue=.*polecat='; then
  pass "cmd_sling _notify_openclaw includes rig, issue, and polecat in message"
else
  fail "cmd_sling _notify_openclaw missing required fields (rig, issue, polecat)"
fi

if echo "$sling_body" | grep -q '_notify_openclaw.*issue_url='; then
  pass "cmd_sling _notify_openclaw includes issue_url"
else
  fail "cmd_sling _notify_openclaw missing issue_url"
fi

if echo "$sling_body" | grep -q '_notify_openclaw ".*" "\$rig"'; then
  pass "cmd_sling _notify_openclaw passes rig for agent routing"
else
  fail "cmd_sling _notify_openclaw not passing rig for routing"
fi

# ── Summary ──
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "ALL TESTS PASSED"
