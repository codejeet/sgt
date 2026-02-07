#!/usr/bin/env bash
# test_mayor_notifications.sh — Verify mayor wake notifications wiring
# Static analysis only; no GitHub access required.

set -euo pipefail
SGT_SCRIPT="$(dirname "$0")/sgt"
PASS=0
FAIL=0

check() {
  local desc="$1" pattern="$2"
  if grep -qP "$pattern" "$SGT_SCRIPT"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== mayor wake notification tests ==="
echo ""

echo "--- Wake summary helper ---"
check "_mayor_wake_summary helper exists" '_mayor_wake_summary\(\)'
check "wake summary handles merged" 'merged:pr#'
check "wake summary handles dog-approved" 'dog-approved:'
check "wake summary handles orphan-pr" 'orphan-pr:#'

echo ""
echo "--- Notify on non-periodic wake ---"
check "mayor derives wake summary" 'wake_summary=\$\(_mayor_wake_summary "\$wake_reason"\)'
check "mayor checks non-periodic wake" 'wake_reason" != "periodic"'
check "mayor notifies rigger with wake summary" '_mayor_notify_rigger "\$wake_summary"'

echo ""
echo "--- Results ---"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
