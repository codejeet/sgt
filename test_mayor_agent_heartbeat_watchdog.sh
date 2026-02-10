#!/usr/bin/env bash
# test_mayor_agent_heartbeat_watchdog.sh — Regression checks for stuck witness/refinery heartbeat watchdog dedupe + recovery reset.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/sgt/.sgt"

bash -s "$SGT_SCRIPT" "$HOME_DIR" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
HOME_DIR="$2"
SGT_CONFIG="$HOME_DIR/sgt/.sgt"
SGT_MAYOR_AGENT_HEARTBEAT_WATCHDOG_STATE="$SGT_CONFIG/mayor-agent-heartbeat-watchdog.state"
SGT_MAYOR_AGENT_HEARTBEAT_DEDUPE_SECS=120

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _mayor_agent_heartbeat_dedupe_secs)"
eval "$(extract_fn _mayor_agent_heartbeat_watchdog_key)"
eval "$(extract_fn _mayor_should_notify_agent_heartbeat_watchdog)"
eval "$(extract_fn _mayor_reset_agent_heartbeat_watchdog)"
eval "$(extract_fn _agent_heartbeat_path)"
eval "$(extract_fn _heartbeat_snapshot_file)"
eval "$(extract_fn _agent_heartbeat_snapshot)"

if ! _mayor_should_notify_agent_heartbeat_watchdog "witness" "demo-rig"; then
  echo "expected first stale heartbeat escalation to notify" >&2
  exit 1
fi
if _mayor_should_notify_agent_heartbeat_watchdog "witness" "demo-rig"; then
  echo "expected duplicate stale heartbeat escalation to be deduped in-window" >&2
  exit 1
fi

tmp_state="$(mktemp)"
awk -F'\t' 'BEGIN{OFS="\t"} { if ($1=="witness|demo-rig") { $2=$2-121 } print }' "$SGT_MAYOR_AGENT_HEARTBEAT_WATCHDOG_STATE" > "$tmp_state"
mv "$tmp_state" "$SGT_MAYOR_AGENT_HEARTBEAT_WATCHDOG_STATE"

if ! _mayor_should_notify_agent_heartbeat_watchdog "witness" "demo-rig"; then
  echo "expected stale heartbeat escalation to notify after dedupe window expires" >&2
  exit 1
fi

if ! _mayor_should_notify_agent_heartbeat_watchdog "refinery" "demo-rig"; then
  echo "expected independent per-agent dedupe keys" >&2
  exit 1
fi

_mayor_reset_agent_heartbeat_watchdog "witness" "demo-rig"
if ! _mayor_should_notify_agent_heartbeat_watchdog "witness" "demo-rig"; then
  echo "expected recovery reset to allow immediate fresh escalation" >&2
  exit 1
fi

old_ts="$(date -u -d "@$(( $(date +%s) - 200 ))" +%Y-%m-%dT%H:%M:%S+00:00)"
cat > "$SGT_CONFIG/witness-demo-rig-heartbeat.json" <<HB
{
  "timestamp": "$old_ts",
  "cycle": 8,
  "pid": 1234,
  "agent": "witness",
  "rig": "demo-rig"
}
HB

IFS='|' read -r age ts state <<< "$(_agent_heartbeat_snapshot "witness" "demo-rig")"
if [[ "$state" != "ok" ]]; then
  echo "expected heartbeat snapshot to parse correctly" >&2
  exit 1
fi
if [[ "$ts" != "$old_ts" ]]; then
  echo "expected heartbeat snapshot to return exact last heartbeat timestamp" >&2
  exit 1
fi
if [[ ! "$age" =~ ^[0-9]+$ || "$age" -lt 200 ]]; then
  echo "expected heartbeat snapshot to return stale age seconds" >&2
  exit 1
fi
BASH

if ! grep -q 'mayor escalated: .* heartbeat stale stale_seconds=.* last_heartbeat=.* runbook_action=notify' "$SGT_SCRIPT"; then
  echo "expected stale heartbeat escalation message to include stale_seconds + last_heartbeat context" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
