#!/usr/bin/env bash
# test_ralph_mode_latest_main_proof.sh — Prove Ralph mode config/state/accounting behavior on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

bash "$REPO_ROOT/test_ralph_mode_config_and_state.sh"
bash "$REPO_ROOT/test_president_runtime_supervision.sh"
bash "$REPO_ROOT/test_mayor_stranded_zero_worker_recovery.sh"
node "$REPO_ROOT/web/test/cockpit.test.js"

echo "RALPH MODE LATEST-MAIN PROOF PASSED"
