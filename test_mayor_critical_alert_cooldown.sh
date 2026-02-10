#!/usr/bin/env bash
# test_mayor_critical_alert_cooldown.sh — Regression checks for mayor critical alert cooldown + heartbeat threshold config parsing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _deacon_heartbeat_stale_secs)"
eval "$(extract_fn _mayor_critical_alert_cooldown_secs)"
eval "$(extract_fn _mayor_notify_critical_guarded)"

SGT_ROOT="$TMP_ROOT/home/sgt"
SGT_CONFIG="$SGT_ROOT/.sgt"
mkdir -p "$SGT_CONFIG"

NOTIFY_LOG="$TMP_ROOT/notify.log"
EVENT_LOG="$TMP_ROOT/events.log"

_mayor_notify_rigger() {
  local message="${1:-}"
  echo "$message" >> "$NOTIFY_LOG"
}

log_event() {
  local message="$*"
  echo "$message" >> "$EVENT_LOG"
}

echo "=== cooldown dedupe (one notify per window) ==="
SGT_MAYOR_CRITICAL_ALERT_COOLDOWN=60
_mayor_notify_critical_guarded "critical/high issues open"
_mayor_notify_critical_guarded "critical/high issues open"

count=$(wc -l < "$NOTIFY_LOG" | tr -d ' ')
if [[ "$count" -ne 1 ]]; then
  echo "expected one notification within cooldown, got $count" >&2
  exit 1
fi

# Simulate cooldown expiry.
old_epoch=$(( $(date +%s) - 61 ))
printf '%s\n' "$old_epoch" > "$SGT_CONFIG/mayor-critical-alert.last"
_mayor_notify_critical_guarded "critical/high issues open"

count=$(wc -l < "$NOTIFY_LOG" | tr -d ' ')
if [[ "$count" -ne 2 ]]; then
  echo "expected notification after cooldown expiry, got $count" >&2
  exit 1
fi

echo "=== cooldown disabled (always notify) ==="
SGT_MAYOR_CRITICAL_ALERT_COOLDOWN=0
_mayor_notify_critical_guarded "critical/high issues open"
_mayor_notify_critical_guarded "critical/high issues open"

count=$(wc -l < "$NOTIFY_LOG" | tr -d ' ')
if [[ "$count" -ne 4 ]]; then
  echo "expected notifications on every call with cooldown=0, got $count" >&2
  exit 1
fi

echo "=== heartbeat threshold config parsing ==="
SGT_DEACON_HEARTBEAT_STALE_SECS=42
if [[ "$(_deacon_heartbeat_stale_secs)" != "42" ]]; then
  echo "expected configured heartbeat stale threshold to be used" >&2
  exit 1
fi

SGT_DEACON_HEARTBEAT_STALE_SECS=bad
if [[ "$(_deacon_heartbeat_stale_secs)" != "300" ]]; then
  echo "expected invalid heartbeat threshold to fall back to default 300" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
