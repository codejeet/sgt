#!/usr/bin/env bash
# test_president_operator_notify_contract.sh — Verify the President operator-notify model and dedupe rules stay documented in-repo.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOC="$REPO_ROOT/docs/president-operator-notify-contract.md"
ARCH_DOC="$REPO_ROOT/docs/president-per-rig-mayor-contract.md"
README="$REPO_ROOT/README.md"

[[ -f "$DOC" ]] || {
  echo "missing President operator-notify contract doc: $DOC" >&2
  exit 1
}

grep -q '^Issue: `#320`$' "$DOC"
grep -q '^## Event Shape$' "$DOC"
grep -q 'PRESIDENT_OPERATOR_EVENT' "$DOC"
grep -q '`dedupe_key`' "$DOC"
grep -q '`overlap_key`' "$DOC"
grep -q '^## Event Kinds$' "$DOC"
grep -q '`drift`' "$DOC"
grep -q '`stalled-purpose`' "$DOC"
grep -q '`contradiction`' "$DOC"
grep -q '`intervention`' "$DOC"
grep -q '`escalation`' "$DOC"
grep -q '`human-question`' "$DOC"
grep -q '^## Current Runtime Mapping$' "$DOC"
grep -q '`actionable-no-forward-motion` -> `stalled-purpose`' "$DOC"
grep -q '`actionable-rig-recheck` -> `intervention`, `severity=info`, `notify=0`' "$DOC"
grep -q '^## Dedupe Rules$' "$DOC"
grep -q 'President-local dedupe uses `dedupe_key`' "$DOC"
grep -q 'Cross-layer dedupe uses `overlap_key`' "$DOC"
grep -q 'only one visible operator notification should survive' "$DOC"
grep -q 'outcome=suppressed-by-cooldown' "$DOC"

grep -q 'docs/president-operator-notify-contract.md' "$ARCH_DOC"
grep -q './test_president_operator_notify_contract.sh' "$ARCH_DOC"
grep -q 'docs/president-operator-notify-contract.md' "$README"
grep -q 'PRESIDENT_OPERATOR_EVENT' "$README"

echo "ALL TESTS PASSED"
