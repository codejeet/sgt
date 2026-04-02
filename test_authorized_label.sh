#!/usr/bin/env bash
# test_authorized_label.sh — Verify sgt-authorized label gate implementation
#
# This is a static analysis test that verifies all security gates are present
# in the sgt script. It doesn't require a running instance or GitHub access.

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

echo "=== sgt-authorized label gate tests ==="
echo ""

echo "--- Helper functions ---"
check "_has_sgt_authorized helper exists" '_has_sgt_authorized\(\)'
check "_ensure_sgt_authorized_label helper exists" '_ensure_sgt_authorized_label\(\)'
check "forge label helper exists" '_forge_label_create\(\)'
check "forge issue label lookup helper exists" '_forge_issue_labels\(\)'
check "_gh_issue_labels_live routes through forge issue label lookup" 'labels=\$\(_forge_issue_labels "\$backend" "\$repo" "\$issue"'
check "_ensure_labels_exist routes through forge label helper" '_forge_label_create "\$backend" "\$repo" "\$label"'

echo ""
echo "--- Label auto-application on issue creation ---"
check "cmd_sling adds sgt-authorized to labels array" 'labels\+=\("sgt-authorized"\)'
check "cmd_sling ensures label exists before creating issue" '_ensure_sgt_authorized_label "\$repo"'
check "cmd_dog creates issues through forge seam" '_forge_issue_create ".*" "\$repo" "\[Dog\]'
check "cmd_molecule_run creates issues through forge seam" '_forge_issue_create ".*" "\$repo" "\[\$\{molecule\}/\$\{step_idx\}\]'

echo ""
echo "--- Security gates (blocking unauthorized work) ---"
check "Witness orphan scan checks for sgt-authorized" 'WITNESS_ORPHAN_SKIP_UNAUTHORIZED'
check "Witness orphan scan skips PRs with no linked issue" 'WITNESS_ORPHAN_SKIP_NO_ISSUE'
check "Resling checks for sgt-authorized before re-dispatch" 'RESLING_SKIP_UNAUTHORIZED'
check "Refinery PR processing checks for sgt-authorized" 'REFINERY_SKIP_UNAUTHORIZED'
check "Refinery PR processing skips PRs with no linked issue" 'REFINERY_SKIP_NO_ISSUE'
check "Refinery dog review checks for sgt-authorized" 'REFINERY_DOG_SKIP_UNAUTHORIZED'
check "Mayor critical issue scan filters by sgt-authorized" 'sgt-authorized,critical'
check "Mayor critical issue scan filters high by sgt-authorized" 'sgt-authorized,high'
check "Mayor briefing filters issues by sgt-authorized" 'label "sgt-authorized".*json number,title,labels'
check "Mayor orphan PR scan checks for sgt-authorized" 'MAYOR_ORPHAN_SKIP_UNAUTHORIZED'
check "Mayor orphan PR scan skips PRs with no linked issue" 'MAYOR_ORPHAN_SKIP_NO_ISSUE'

echo ""
echo "--- Label initialization ---"
check "cmd_rig_add creates sgt-authorized label" '_ensure_sgt_authorized_label "\$repo"'
check "cmd_escalation_init creates sgt-authorized label" '_ensure_sgt_authorized_label "\$repo"'
check "cmd_label_init function exists" 'cmd_label_init\(\)'
check "sgt label init command routed" 'label\)'
check "forge label command exists" 'cmd_forge_label\(\)'

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
