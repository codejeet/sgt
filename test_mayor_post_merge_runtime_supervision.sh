#!/usr/bin/env bash
# test_mayor_post_merge_runtime_supervision.sh — Regression checks for mayor restart + exit telemetry after a successful merge cycle.

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

eval "$(extract_fn _mayor_last_cycle_state_file)"
eval "$(extract_fn _mayor_last_cycle_state_read)"
eval "$(extract_fn _mayor_last_cycle_state_write)"
eval "$(extract_fn _mayor_exit_state_file)"
eval "$(extract_fn _mayor_exit_state_read)"
eval "$(extract_fn _mayor_exit_state_write)"
eval "$(extract_fn _mayor_heartbeat_file)"
eval "$(extract_fn _mayor_heartbeat_stale_secs)"
eval "$(extract_fn _mayor_heartbeat_snapshot)"
eval "$(extract_fn _mayor_heartbeat_health)"
eval "$(extract_fn _mayor_exit_receipt)"
eval "$(extract_fn _deacon_supervise_mayor)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
mkdir -p "$SGT_CONFIG"
EVENT_LOG="$TMP_ROOT/events.log"
START_LOG="$TMP_ROOT/start.log"
export SGT_ROOT SGT_CONFIG EVENT_LOG START_LOG

log_event() {
  echo "$*" >> "$EVENT_LOG"
}

_mayor_record_decision() {
  :
}

_escape_quotes() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

_escape_wake_value() {
  local value="${1:-}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//|/%7C}"
  printf '%s' "$value"
}

cmd_mayor_start() {
  echo "started" >> "$START_LOG"
}

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" && "${3:-}" == "sgt-mayor" ]]; then
    return 1
  fi
  return 0
}

_MAYOR_EXIT_RECEIPT_LOGGED=0
_mayor_last_cycle_state_write "merged:pr#192:#191:sgt|repo=codejeet/sgt" "completed"
_mayor_exit_receipt 17 EXIT
_deacon_supervise_mayor > "$TMP_ROOT/deacon.out"

if [[ "$(wc -l < "$START_LOG")" -ne 1 ]]; then
  echo "expected deacon supervision to restart mayor once" >&2
  exit 1
fi
if ! grep -q 'DEACON_RESTART_MAYOR reason=session-missing .*last_exit_reason=nonzero-exit' "$EVENT_LOG"; then
  echo "expected deacon restart event with durable exit reason" >&2
  exit 1
fi
if ! grep -q 'last_cycle_trigger="merged:pr#192:#191:sgt%7Crepo=codejeet/sgt"' "$EVENT_LOG"; then
  echo "expected deacon restart event to include merged-cycle trigger context" >&2
  exit 1
fi
if ! grep -q 'last_cycle_status=completed' "$EVENT_LOG"; then
  echo "expected deacon restart event to include last cycle status" >&2
  exit 1
fi
if ! grep -q 'last_exit=nonzero-exit signal=EXIT code=17' "$TMP_ROOT/deacon.out"; then
  echo "expected operator-visible restart line to include exit telemetry" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
