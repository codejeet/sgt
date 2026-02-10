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

check_runtime_collision() {
  local desc="$1"
  if bash -s "$SGT_SCRIPT" <<'BASH'
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
eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _wake_field)"
eval "$(extract_fn _mayor_wake_summary)"

r1='merged:pr#77:#40:rig-a|repo=org/repo-one|title=Fix shared id|pr_url=https://github.com/org/repo-one/pull/77|issue_url=https://github.com/org/repo-one/issues/40'
r2='merged:pr#77:#40:rig-b|repo=org/repo-two|title=Fix shared id|pr_url=https://github.com/org/repo-two/pull/77|issue_url=https://github.com/org/repo-two/issues/40'
s1=$(_mayor_wake_summary "$r1")
s2=$(_mayor_wake_summary "$r2")
[[ "$s1" != "$s2" ]]
[[ "$s1" == *"repo=org/repo-one"* ]]
[[ "$s2" == *"repo=org/repo-two"* ]]
[[ "$s1" == *"pr_url=https://github.com/org/repo-one/pull/77"* ]]
[[ "$s2" == *"pr_url=https://github.com/org/repo-two/pull/77"* ]]
[[ "$s1" == *"issue_url=https://github.com/org/repo-one/issues/40"* ]]
[[ "$s2" == *"issue_url=https://github.com/org/repo-two/issues/40"* ]]
BASH
  then
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
check "wake summary reads repo from wake payload" '_wake_field "\$reason" "repo"'
check "wake summary includes required merge metadata fields" 'rig=\$rig repo=\$\{repo:-unknown\} pr=#\$pr title='
check "wake summary includes direct PR URL" 'pr_url=\$\{pr_url:-unknown\}'
check "wake summary includes direct issue URL" 'issue_url=\$\{issue_url:-unknown\}'

echo ""
echo "--- Notify on non-periodic wake ---"
check "mayor derives wake summary" 'wake_summary=\$\(_mayor_wake_summary "\$wake_reason"\)'
check "mayor checks non-periodic wake" 'wake_reason" != "periodic"'
check "mayor notifies rigger with wake summary" '_mayor_notify_rigger "\$wake_summary"'

echo ""
echo "--- Refinery templates ---"
check "refinery review-approved notification includes required fields" 'review approved rig=\$rig repo=\$owner_repo pr=#\$pr title='
check "refinery review-approved notification includes direct URLs" 'review approved.*pr_url=\$pr_url issue_url=\$issue_url'
check "refinery merged notification includes required fields" 'merged rig=\$rig repo=\$mq_owner_repo pr=#\$mq_pr title='
check "refinery merged notification includes direct URLs" 'merged.*pr_url=\$mq_pr_url issue_url=\$mq_issue_url'
check "merged wake reason appends repo/title/url context" '_wake_mayor "merged:pr#\$mq_pr:#\$mq_issue:\$rig\|repo='
check_runtime_collision "two rigs with same PR/issue numbers produce unambiguous wake summaries"

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
