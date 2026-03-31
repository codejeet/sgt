#!/usr/bin/env bash
# test_web_cockpit_control_plane_hierarchy.sh — Verify the Web UI keeps President and rig-local Mayor hierarchy inspectable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

node --test "$REPO_ROOT/web/test/cockpit.test.js"

echo "WEB COCKPIT CONTROL-PLANE HIERARCHY TESTS PASSED"
