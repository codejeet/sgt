#!/usr/bin/env bash
# test_president_per_rig_mayor_contract.sh — Verify the President/per-rig Mayor architecture contract stays documented in-repo.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOC="$REPO_ROOT/docs/president-per-rig-mayor-contract.md"
README="$REPO_ROOT/README.md"

[[ -f "$DOC" ]] || {
  echo "missing architecture contract doc: $DOC" >&2
  exit 1
}

grep -q '^Issue: `#300`$' "$DOC"
grep -q '^## Current Transitional State$' "$DOC"
grep -q 'the default runtime is still the legacy shared Mayor' "$DOC"
grep -q 'SGT_MAYOR_ARCHITECTURE=per-rig' "$DOC"
grep -q 'no first-class President runtime or operator surface exists yet' "$DOC"
grep -q '^## Target Hierarchy$' "$DOC"
grep -q 'President -> Mayor/<rig> -> rig-local workers' "$DOC"
grep -q '^### President$' "$DOC"
grep -q 'must not:' "$DOC"
grep -q 'take over routine repo-local execution from a rig Mayor' "$DOC"
grep -q '^### Mayor/<rig>$' "$DOC"
grep -q 'Each Mayor must have scoped runtime assets under a rig-local directory' "$DOC"
grep -q '^## Operator Scope Contract$' "$DOC"
grep -q '`sgt status` distinguishes President from each `mayor/<rig>`' "$DOC"
grep -q '`sgt peek` and log surfaces let the operator inspect `president` separately from `mayor/<rig>`' "$DOC"
grep -q '^## Migration Safety Rules$' "$DOC"
grep -q 'do not manufacture duplicate work during topology changes' "$DOC"
grep -q '^## Repo-Owned Proof Expectations$' "$DOC"
grep -q './test_president_per_rig_mayor_contract_latest_main_proof.sh' "$DOC"

grep -q 'docs/president-per-rig-mayor-contract.md' "$README"
grep -q './test_president_per_rig_mayor_contract_latest_main_proof.sh' "$README"
grep -q 'This is transition scaffolding toward the documented `President -> mayor/<rig>` hierarchy' "$README"

echo "ALL TESTS PASSED"
