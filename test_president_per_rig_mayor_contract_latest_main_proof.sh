#!/usr/bin/env bash
# test_president_per_rig_mayor_contract_latest_main_proof.sh — Prove the President/per-rig Mayor architecture contract on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

bash "$REPO_ROOT/test_president_per_rig_mayor_contract.sh"
bash "$REPO_ROOT/test_mayor_per_rig_architecture.sh"

echo "PRESIDENT/PER-RIG MAYOR CONTRACT LATEST-MAIN PROOF PASSED"
