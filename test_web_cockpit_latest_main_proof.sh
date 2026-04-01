#!/usr/bin/env bash
# test_web_cockpit_latest_main_proof.sh — Prove the repo-tracked web cockpit docs, tests, and deploy helper on a latest-main checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

npm --prefix "$REPO_ROOT/web" ci
npm --prefix "$REPO_ROOT/web" test
SGT_WEB_REPO_DIR="$REPO_ROOT" SGT_WEB_LIVE_DIR="$TMP_DIR/live" "$REPO_ROOT/sgt" web deploy --dry-run

echo "WEB COCKPIT LATEST-MAIN PROOF PASSED"
