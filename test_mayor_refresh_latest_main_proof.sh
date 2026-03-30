#!/usr/bin/env bash
# test_mayor_refresh_latest_main_proof.sh — Latest-main proof bundle for Mayor refresh + runtime auto-refresh behavior.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

bash ./test_mayor_refresh.sh
bash ./test_mayor_runtime_auto_refresh.sh
bash ./test_mayor_auto_refresh_threshold.sh
bash ./test_status_json.sh

echo "LATEST MAIN MAYOR REFRESH PROOF PASSED"
