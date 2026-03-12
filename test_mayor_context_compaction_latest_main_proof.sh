#!/usr/bin/env bash
# test_mayor_context_compaction_latest_main_proof.sh — Prove Mayor context compaction on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

bash "$REPO_ROOT/test_mayor_briefing_budget_contract.sh"

echo "MAYOR CONTEXT COMPACTION LATEST-MAIN PROOF PASSED"
