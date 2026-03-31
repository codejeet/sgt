#!/usr/bin/env bash
# test_president_runtime_latest_main_proof.sh — Prove President + per-rig Mayor runtime hierarchy on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

bash "$REPO_ROOT/test_mayor_per_rig_architecture.sh"
bash "$REPO_ROOT/test_president_runtime_supervision.sh"
bash "$REPO_ROOT/test_president_cutover_migration_guard.sh"
bash "$REPO_ROOT/test_peek_mayor_log_fallback.sh"
bash "$REPO_ROOT/test_president_per_rig_mayor_contract.sh"

echo "ALL TESTS PASSED"
