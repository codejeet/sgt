#!/usr/bin/env bash
# test_self_test_convoy_latest_main_proof.sh — Prove the SGT self-test convoy workflow on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

bash "$REPO_ROOT/test_plan_completion_acceptance_lifecycle.sh"
bash "$REPO_ROOT/test_worker_prompt_completion_context.sh"
bash "$REPO_ROOT/test_mayor_completion_condition_regression.sh"
bash "$REPO_ROOT/test_mayor_briefing_budget_contract.sh"

echo "SELF-TEST CONVOY LATEST-MAIN PROOF PASSED"
