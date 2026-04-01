#!/usr/bin/env bash
# test_president_runtime_latest_main_proof.sh — Prove President + per-rig Mayor runtime hierarchy on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

bash "$REPO_ROOT/test_mayor_per_rig_architecture.sh"
bash "$REPO_ROOT/test_hierarchy_cutover_guardrails.sh"
bash "$REPO_ROOT/test_mayor_helper_state_preservation.sh"
bash "$REPO_ROOT/test_president_runtime_supervision.sh"
bash "$REPO_ROOT/test_peek_mayor_log_fallback.sh"
bash "$REPO_ROOT/test_web_cockpit_control_plane_hierarchy.sh"
bash "$REPO_ROOT/test_president_per_rig_mayor_contract.sh"
bash "$REPO_ROOT/test_president_operator_notify_contract.sh"

echo "ALL TESTS PASSED"
