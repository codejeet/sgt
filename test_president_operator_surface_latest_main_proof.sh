#!/usr/bin/env bash
# test_president_operator_surface_latest_main_proof.sh — Prove the President operator-surface pass on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

bash "$REPO_ROOT/test_president_runtime_latest_main_proof.sh"
bash "$REPO_ROOT/test_status_json.sh"
npm --prefix "$REPO_ROOT/web" test
bash "$REPO_ROOT/test_president_operator_surface_contract.sh"

echo "PRESIDENT OPERATOR-SURFACE LATEST-MAIN PROOF PASSED"
