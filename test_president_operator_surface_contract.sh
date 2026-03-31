#!/usr/bin/env bash
# test_president_operator_surface_contract.sh — Verify the President operator-surface contract stays documented in-repo.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOC="$REPO_ROOT/docs/president-operator-surface-contract.md"
README="$REPO_ROOT/README.md"
WEB_README="$REPO_ROOT/web/README.md"

[[ -f "$DOC" ]] || {
  echo "missing President operator-surface contract doc: $DOC" >&2
  exit 1
}

grep -q '^Issue: `#333`$' "$DOC"
grep -q '^## Required Surfaces$' "$DOC"
grep -q '`sgt status` shows `president` separately from each `mayor/<rig>`' "$DOC"
grep -q '`sgt status --json` emits control-plane `role` / `scope` metadata plus bounded `president_events` history' "$DOC"
grep -q '`sgt peek president` and `sgt peek mayor/<rig>` retain scoped inspection' "$DOC"
grep -q 'Web UI `President Activity` panel renders recent President event history' "$DOC"
grep -q '^## Latest-Main Proof$' "$DOC"
grep -q './test_president_operator_surface_latest_main_proof.sh' "$DOC"
grep -q './test_president_runtime_latest_main_proof.sh' "$DOC"
grep -q './test_status_json.sh' "$DOC"
grep -q 'npm --prefix web test' "$DOC"
grep -q 'docs/president-per-rig-mayor-contract.md' "$DOC"
grep -q 'docs/president-operator-notify-contract.md' "$DOC"

grep -q 'docs/president-operator-surface-contract.md' "$README"
grep -q './test_president_operator_surface_latest_main_proof.sh' "$README"
grep -q 'President Activity' "$README"

grep -q 'docs/president-operator-surface-contract.md' "$WEB_README"
grep -q './test_president_operator_surface_latest_main_proof.sh' "$WEB_README"
grep -q 'President Activity' "$WEB_README"

echo "ALL TESTS PASSED"
