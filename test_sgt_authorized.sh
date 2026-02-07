#!/usr/bin/env bash
# Tests for the sgt-authorized label gate feature
#
# These tests validate that the _has_sgt_authorized helper function
# and the label gate checks work correctly by mocking the gh CLI.
set -euo pipefail

PASS=0
FAIL=0
TESTS=0

pass() { PASS=$((PASS + 1)); TESTS=$((TESTS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS=$((TESTS + 1)); echo "  FAIL: $1"; }

# ─── Setup ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$SCRIPT_DIR/sgt"

# Create a temp directory for mock gh
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_GH="$TMPDIR/gh"

# ─── Test 1: _has_sgt_authorized returns true when label is present ──

echo "Test 1: _has_sgt_authorized with sgt-authorized label present"
cat > "$MOCK_GH" <<'EOF'
#!/bin/bash
# Mock gh: returns sgt-authorized label
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo "sgt-authorized"
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_GH"

# Source only the helper function and run it
result=$(PATH="$TMPDIR:$PATH" bash -c '
  _has_sgt_authorized() {
    local repo="$1" issue="$2"
    [[ -n "$issue" && "$issue" != "0" ]] || return 1
    local labels
    labels=$(gh issue view "$issue" --repo "$repo" --json labels --jq ".labels[].name" 2>/dev/null || true)
    echo "$labels" | grep -qx "sgt-authorized"
  }
  _has_sgt_authorized "owner/repo" "42" && echo "AUTHORIZED" || echo "NOT_AUTHORIZED"
')
if [[ "$result" == "AUTHORIZED" ]]; then
  pass "_has_sgt_authorized returns true when label present"
else
  fail "_has_sgt_authorized should return true when label present (got: $result)"
fi

# ─── Test 2: _has_sgt_authorized returns false when label is absent ──

echo "Test 2: _has_sgt_authorized without sgt-authorized label"
cat > "$MOCK_GH" <<'EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo "bug"
  echo "enhancement"
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_GH"

result=$(PATH="$TMPDIR:$PATH" bash -c '
  _has_sgt_authorized() {
    local repo="$1" issue="$2"
    [[ -n "$issue" && "$issue" != "0" ]] || return 1
    local labels
    labels=$(gh issue view "$issue" --repo "$repo" --json labels --jq ".labels[].name" 2>/dev/null || true)
    echo "$labels" | grep -qx "sgt-authorized"
  }
  _has_sgt_authorized "owner/repo" "42" && echo "AUTHORIZED" || echo "NOT_AUTHORIZED"
')
if [[ "$result" == "NOT_AUTHORIZED" ]]; then
  pass "_has_sgt_authorized returns false when label absent"
else
  fail "_has_sgt_authorized should return false when label absent (got: $result)"
fi

# ─── Test 3: _has_sgt_authorized returns false for issue 0 ───────────

echo "Test 3: _has_sgt_authorized rejects issue number 0"
result=$(PATH="$TMPDIR:$PATH" bash -c '
  _has_sgt_authorized() {
    local repo="$1" issue="$2"
    [[ -n "$issue" && "$issue" != "0" ]] || return 1
    local labels
    labels=$(gh issue view "$issue" --repo "$repo" --json labels --jq ".labels[].name" 2>/dev/null || true)
    echo "$labels" | grep -qx "sgt-authorized"
  }
  _has_sgt_authorized "owner/repo" "0" && echo "AUTHORIZED" || echo "NOT_AUTHORIZED"
')
if [[ "$result" == "NOT_AUTHORIZED" ]]; then
  pass "_has_sgt_authorized rejects issue 0"
else
  fail "_has_sgt_authorized should reject issue 0 (got: $result)"
fi

# ─── Test 4: _has_sgt_authorized returns false for empty issue ───────

echo "Test 4: _has_sgt_authorized rejects empty issue"
result=$(PATH="$TMPDIR:$PATH" bash -c '
  _has_sgt_authorized() {
    local repo="$1" issue="$2"
    [[ -n "$issue" && "$issue" != "0" ]] || return 1
    local labels
    labels=$(gh issue view "$issue" --repo "$repo" --json labels --jq ".labels[].name" 2>/dev/null || true)
    echo "$labels" | grep -qx "sgt-authorized"
  }
  _has_sgt_authorized "owner/repo" "" && echo "AUTHORIZED" || echo "NOT_AUTHORIZED"
')
if [[ "$result" == "NOT_AUTHORIZED" ]]; then
  pass "_has_sgt_authorized rejects empty issue"
else
  fail "_has_sgt_authorized should reject empty issue (got: $result)"
fi

# ─── Test 5: _has_sgt_authorized doesn't match partial label names ───

echo "Test 5: _has_sgt_authorized rejects partial matches"
cat > "$MOCK_GH" <<'EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo "not-sgt-authorized"
  echo "sgt-authorized-extra"
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_GH"

result=$(PATH="$TMPDIR:$PATH" bash -c '
  _has_sgt_authorized() {
    local repo="$1" issue="$2"
    [[ -n "$issue" && "$issue" != "0" ]] || return 1
    local labels
    labels=$(gh issue view "$issue" --repo "$repo" --json labels --jq ".labels[].name" 2>/dev/null || true)
    echo "$labels" | grep -qx "sgt-authorized"
  }
  _has_sgt_authorized "owner/repo" "42" && echo "AUTHORIZED" || echo "NOT_AUTHORIZED"
')
if [[ "$result" == "NOT_AUTHORIZED" ]]; then
  pass "_has_sgt_authorized rejects partial label matches"
else
  fail "_has_sgt_authorized should reject partial matches (got: $result)"
fi

# ─── Test 6: _has_sgt_authorized works with multiple labels ──────────

echo "Test 6: _has_sgt_authorized finds label among multiple"
cat > "$MOCK_GH" <<'EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo "bug"
  echo "sgt-authorized"
  echo "critical"
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_GH"

result=$(PATH="$TMPDIR:$PATH" bash -c '
  _has_sgt_authorized() {
    local repo="$1" issue="$2"
    [[ -n "$issue" && "$issue" != "0" ]] || return 1
    local labels
    labels=$(gh issue view "$issue" --repo "$repo" --json labels --jq ".labels[].name" 2>/dev/null || true)
    echo "$labels" | grep -qx "sgt-authorized"
  }
  _has_sgt_authorized "owner/repo" "42" && echo "AUTHORIZED" || echo "NOT_AUTHORIZED"
')
if [[ "$result" == "AUTHORIZED" ]]; then
  pass "_has_sgt_authorized finds label among multiple labels"
else
  fail "_has_sgt_authorized should find label among multiple (got: $result)"
fi

# ─── Test 7: Verify sgt-authorized label in cmd_sling issue creation ─

echo "Test 7: cmd_sling includes sgt-authorized label in issue creation"
if grep -q 'labels+=("sgt-authorized")' "$SGT_SCRIPT"; then
  pass "cmd_sling adds sgt-authorized to labels array"
else
  fail "cmd_sling should add sgt-authorized to labels array"
fi

# ─── Test 8: Verify _resling_existing_issue has label gate ───────────

echo "Test 8: _resling_existing_issue checks for sgt-authorized"
if grep -A5 '_resling_existing_issue()' "$SGT_SCRIPT" | grep -q '_has_sgt_authorized'; then
  pass "_resling_existing_issue has sgt-authorized gate"
else
  fail "_resling_existing_issue should check sgt-authorized label"
fi

# ─── Test 9: Verify refinery has label gate ──────────────────────────

echo "Test 9: Refinery PR processing checks for sgt-authorized"
if grep -B2 -A5 'Security gate: verify issue has sgt-authorized label' "$SGT_SCRIPT" | grep -q '_has_sgt_authorized'; then
  pass "Refinery has sgt-authorized gate for PR processing"
else
  fail "Refinery should check sgt-authorized for PR processing"
fi

# ─── Test 10: Verify witness orphan PR scanner has label gate ────────

echo "Test 10: Witness orphan PR scanner checks for sgt-authorized"
if grep -A10 'BLOCKED orphan PR' "$SGT_SCRIPT" | grep -q 'sgt-authorized'; then
  pass "Witness orphan PR scanner has sgt-authorized gate"
else
  fail "Witness orphan PR scanner should check sgt-authorized"
fi

# ─── Test 11: Mayor critical issue scan uses sgt-authorized filter ───

echo "Test 11: Mayor critical issue scan filters by sgt-authorized"
if grep 'critical,high,sgt-authorized' "$SGT_SCRIPT" | grep -q 'gh issue list'; then
  pass "Mayor critical issue scan filters by sgt-authorized label"
else
  fail "Mayor critical issue scan should filter by sgt-authorized"
fi

# ─── Test 12: Dog dispatch includes sgt-authorized label ─────────────

echo "Test 12: Dog dispatch adds sgt-authorized label"
if grep -A3 'label "dog" --label "sgt-authorized"' "$SGT_SCRIPT" >/dev/null 2>&1; then
  pass "Dog dispatch includes sgt-authorized label"
else
  fail "Dog dispatch should include sgt-authorized label"
fi

# ─── Test 13: Molecule dispatch includes sgt-authorized label ────────

echo "Test 13: Molecule dispatch adds sgt-authorized label"
if grep -B5 'label "sgt-authorized"' "$SGT_SCRIPT" | grep -q 'molecule'; then
  pass "Molecule dispatch includes sgt-authorized label"
else
  fail "Molecule dispatch should include sgt-authorized label"
fi

# ─── Test 14: Mayor briefing only shows sgt-authorized issues ────────

echo "Test 14: Mayor briefing filters issues by sgt-authorized"
if sed -n '/_mayor_build_briefing/,/^}/p' "$SGT_SCRIPT" | grep -q 'issue list.*--label sgt-authorized'; then
  pass "Mayor briefing filters by sgt-authorized"
else
  fail "Mayor briefing should filter issues by sgt-authorized"
fi

# ─── Test 15: Refinery dog review has label gate ─────────────────────

echo "Test 15: Refinery dog review checks sgt-authorized"
if grep -B2 -A5 'BLOCKED dog.*missing sgt-authorized' "$SGT_SCRIPT" >/dev/null 2>&1; then
  pass "Refinery dog review has sgt-authorized gate"
else
  fail "Refinery dog review should check sgt-authorized"
fi

# ─── Test 16: Escalation init creates sgt-authorized label ───────────

echo "Test 16: Escalation init creates sgt-authorized label"
if sed -n '/^cmd_escalation_init/,/^cmd_escalation_show/p' "$SGT_SCRIPT" | grep -q 'sgt-authorized'; then
  pass "Escalation init creates sgt-authorized label"
else
  fail "Escalation init should create sgt-authorized label"
fi

# ─── Summary ─────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed ($TESTS total)"
echo "════════════════════════════════"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
