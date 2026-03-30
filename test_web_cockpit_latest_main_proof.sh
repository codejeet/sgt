#!/usr/bin/env bash
# test_web_cockpit_latest_main_proof.sh — Prove the repo-tracked web cockpit docs, tests, and deploy helper on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

npm --prefix "$REPO_ROOT/web" test
"$REPO_ROOT/web/scripts/sync-live-copy.sh" --dry-run "$TMP_DIR/live"

echo "WEB COCKPIT LATEST-MAIN PROOF PASSED"
