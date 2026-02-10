#!/usr/bin/env bash
# test_mayor_cycle_lock_lease.sh — Regression checks for mayor lease lock recovery and stale steal.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _mayor_lock_lease_secs)"
eval "$(extract_fn _mayor_lock_owner_live)"
eval "$(extract_fn _mayor_lock_read)"
eval "$(extract_fn _mayor_lock_write)"
eval "$(extract_fn _mayor_lock_claim)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SGT_ROOT="$TMP_DIR/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_MAYOR_LOCK="$SGT_CONFIG/mayor.lock"
mkdir -p "$SGT_CONFIG"

# Dead-owner stale-lock steal: existing owner pid is not live.
_mayor_lock_write "$SGT_MAYOR_LOCK" "999999" "100" "$(( $(date +%s) + 60 ))"
claim="$(_mayor_lock_claim)"
IFS='|' read -r decision owner started lease reason <<< "$claim"
if [[ "$decision" != "stolen" || "$reason" != "owner-dead" ]]; then
  echo "expected dead-owner lock steal, got: $claim" >&2
  exit 1
fi
if [[ "$owner" != "$$" ]]; then
  echo "expected current pid to become lock owner after steal" >&2
  exit 1
fi

# Live-owner lock must be respected while lease is still valid.
sleep 60 &
live_pid=$!
_mayor_lock_write "$SGT_MAYOR_LOCK" "$live_pid" "200" "$(( $(date +%s) + 120 ))"
set +e
claim="$(_mayor_lock_claim)"
rc=$?
set -e
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
if [[ "$rc" -eq 0 ]]; then
  echo "expected claim to fail when owner is live and lease valid" >&2
  exit 1
fi
IFS='|' read -r decision owner started lease reason <<< "$claim"
if [[ "$decision" != "blocked-live" ]]; then
  echo "expected blocked-live decision, got: $claim" >&2
  exit 1
fi

# Lease-expiry boundary: owner still live but leaseUntil == now allows steal.
sleep 60 &
live_pid=$!
now="$(date +%s)"
_mayor_lock_write "$SGT_MAYOR_LOCK" "$live_pid" "300" "$now"
claim="$(_mayor_lock_claim)"
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
IFS='|' read -r decision owner started lease reason <<< "$claim"
if [[ "$decision" != "stolen" || "$reason" != "lease-expired" ]]; then
  echo "expected lease-expired boundary steal, got: $claim" >&2
  exit 1
fi
BASH

if ! grep -q '\[mayor\] lock decision: \${lock_decision}' "$SGT_SCRIPT"; then
  echo "expected explicit mayor lock decision status line" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
