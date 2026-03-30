#!/usr/bin/env bash
# test_mayor_refresh_latest_main_proof.sh — Prove Mayor refresh support on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

bash "$REPO_ROOT/test_mayor_refresh.sh"
bash "$REPO_ROOT/test_mayor_auto_refresh_runtime.sh"

echo "MAYOR REFRESH LATEST-MAIN PROOF PASSED"
