#!/usr/bin/env bash
# test_deacon_rig_hibernation_enforcement.sh — Deacon keeps hibernated rigs cold.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

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

extract_range() {
  local start="$1" end="$2"
  sed -n "/^${start}() {/,/^${end}() {/p" "$SGT_SCRIPT" | sed '$d'
}

eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _mayor_rig_activity_enabled)"
eval "$(extract_fn _mayor_rig_activity_file)"
eval "$(extract_fn _mayor_rig_activity_state_read)"
eval "$(extract_fn _mayor_rig_hibernated)"
eval "$(extract_fn _rig_hibernation_sync_agents)"
eval "$(extract_range _deacon_loop cmd_deacon_start)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_RIGS="$SGT_ROOT/rigs"
SGT_POLECATS="$SGT_ROOT/polecats"
SGT_DEACON_HEARTBEAT="$SGT_ROOT/.sgt/deacon-heartbeat.json"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_MAYOR_RIG_ACTIVITY_DIR="$SGT_CONFIG/mayor-rig-activity"
SESSIONS_DIR="$TMP_ROOT/sessions"
EVENT_LOG="$TMP_ROOT/events.log"
START_LOG="$TMP_ROOT/start.log"
STOP_LOG="$TMP_ROOT/stop.log"
export SGT_ROOT SGT_RIGS SGT_POLECATS SGT_DEACON_HEARTBEAT SGT_CONFIG SGT_MAYOR_RIG_ACTIVITY_DIR
export SESSIONS_DIR EVENT_LOG START_LOG STOP_LOG

mkdir -p "$SGT_RIGS" "$SGT_POLECATS" "$(dirname "$SGT_DEACON_HEARTBEAT")" "$SGT_MAYOR_RIG_ACTIVITY_DIR" "$SESSIONS_DIR"
printf 'org/repo\n' > "$SGT_RIGS/demo"
cat > "$SGT_MAYOR_RIG_ACTIVITY_DIR/demo.state" <<'STATE'
STATE=hibernated
LAST_REASON=quiet window
CHANGED_AT=2026-03-26T04:00:00+01:00
CHANGED_EPOCH=1774494000
HIBERNATION_MODE=manual
LAST_MEANINGFUL_AT=
LAST_MEANINGFUL_EPOCH=
LAST_MEANINGFUL_REASON=
LAST_WAKE_AT=
LAST_WAKE_REASON=
STATE
: > "$SESSIONS_DIR/sgt-witness-demo"
: > "$SESSIONS_DIR/sgt-refinery-demo"
: > "$START_LOG"
: > "$STOP_LOG"

log_event() {
  echo "$*" >> "$EVENT_LOG"
}

cmd_witness_start() {
  echo "witness-start:$1" >> "$START_LOG"
}

cmd_refinery_start() {
  echo "refinery-start:$1" >> "$START_LOG"
}

cmd_witness_stop() {
  echo "witness-stop:$1" >> "$STOP_LOG"
  rm -f "$SESSIONS_DIR/sgt-witness-$1"
}

cmd_refinery_stop() {
  echo "refinery-stop:$1" >> "$STOP_LOG"
  rm -f "$SESSIONS_DIR/sgt-refinery-$1"
}

_deacon_supervise_mayor() {
  return 1
}

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" ]]; then
    [[ -f "$SESSIONS_DIR/${3:-}" ]]
    return $?
  fi
  return 0
}

sleep() {
  kill -TERM "$BASHPID"
  command sleep 0.1
  return 0
}

set +e
_deacon_loop > "$TMP_ROOT/deacon.out" 2>&1 &
wait "$!"
rc=$?
set -e

if [[ "$rc" -ne 143 ]]; then
  echo "expected stubbed sleep to terminate the deacon loop with SIGTERM, got $rc" >&2
  exit 1
fi
if [[ -s "$START_LOG" ]]; then
  echo "expected deacon not to restart witness/refinery for a hibernated rig" >&2
  exit 1
fi
if ! grep -q '^witness-stop:demo$' "$STOP_LOG"; then
  echo "expected deacon to stop witness for hibernated rig" >&2
  exit 1
fi
if ! grep -q '^refinery-stop:demo$' "$STOP_LOG"; then
  echo "expected deacon to stop refinery for hibernated rig" >&2
  exit 1
fi
if [[ -e "$SESSIONS_DIR/sgt-witness-demo" || -e "$SESSIONS_DIR/sgt-refinery-demo" ]]; then
  echo "expected hibernated rig sessions to be removed" >&2
  exit 1
fi
if ! grep -q 'DEACON_ENFORCE_HIBERNATION rig=demo' "$EVENT_LOG"; then
  echo "expected structured deacon hibernation enforcement event" >&2
  exit 1
fi
if ! grep -q '\[deacon\] demo is hibernated — stopping witness/refinery' "$TMP_ROOT/deacon.out"; then
  echo "expected operator-visible deacon hibernation line" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
