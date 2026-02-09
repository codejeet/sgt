#!/usr/bin/env bash
# test_inbox_mode.sh — Verify interactive inbox mode wiring
# Static analysis only; no network or OADM access required.

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

echo "=== interactive inbox mode tests ==="
echo ""

echo "--- Command wiring ---"
check "cmd_inbox function exists" 'cmd_inbox\(\)'
check "top-level inbox command routed" 'inbox\)\s+cmd_inbox "\$@"'
check "mail inbox alias routed" 'inbox\)\s+cmd_inbox "\$@"'

echo ""
echo "--- Data source + formatting ---"
check "inbox fetch uses oadm npx command" 'npx -y @codejeet/oadm@latest inbox --all --json'
check "messages sorted by createdAt" 'sort_by\(\.createdAt\)'
check "messages reversed" '\| reverse\[\]'
check "direction included in formatter" 'direction'
check "fromName included in formatter" 'fromName'
check "toName included in formatter" 'toName'
check "id included in formatter" 'id: `\\\(\.id'
check "createdAt included in formatter" 'created: \\\(\.createdAt'
check "ackedAt included in formatter" 'acked: \\\(\.ackedAt'
check "text included in formatter" '\\\(\.text // ""\)'

echo ""
echo "--- Pager behavior ---"
check "prefers glow pager mode" 'glow -p'
check "falls back to less" 'less -R'
check "supports custom pager override for automation" 'SGT_PAGER'

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
