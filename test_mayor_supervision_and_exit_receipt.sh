#!/usr/bin/env bash
# test_mayor_supervision_and_exit_receipt.sh — Regression checks for mayor supervision + exit receipts.

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

echo "=== deacon restarts missing mayor ==="
bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_range() {
  local start="$1" end="$2"
  sed -n "/^${start}() {/,/^${end}() {/p" "$SGT_SCRIPT" | sed '$d'
}

eval "$(extract_range _deacon_loop cmd_deacon_start)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_RIGS="$SGT_ROOT/rigs"
SGT_POLECATS="$SGT_ROOT/polecats"
SGT_DEACON_HEARTBEAT="$SGT_ROOT/.sgt/deacon-heartbeat.json"
mkdir -p "$SGT_RIGS" "$SGT_POLECATS" "$(dirname "$SGT_DEACON_HEARTBEAT")"
printf 'org/repo\n' > "$SGT_RIGS/demo"

EVENT_LOG="$TMP_ROOT/events.log"
TRACE_LOG="$TMP_ROOT/trace.log"
START_LOG="$TMP_ROOT/mayor-start.log"
export SGT_ROOT SGT_RIGS SGT_POLECATS SGT_DEACON_HEARTBEAT EVENT_LOG TRACE_LOG START_LOG

log_event() {
  echo "$*" >> "$EVENT_LOG"
}

cmd_witness_start() { :; }
cmd_refinery_start() { :; }
cmd_mayor_start() {
  echo "started" >> "$START_LOG"
}

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" ]]; then
    case "${3:-}" in
      sgt-mayor) return 1 ;;
      sgt-witness-demo|sgt-refinery-demo) return 0 ;;
    esac
  fi
  return 0
}

sleep() {
  echo "sleep:$*" >> "$TRACE_LOG"
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
if [[ "$(wc -l < "$START_LOG")" -ne 1 ]]; then
  echo "expected deacon to restart mayor exactly once when session is missing" >&2
  exit 1
fi
if ! grep -q 'DEACON_RESTART_MAYOR' "$EVENT_LOG"; then
  echo "expected structured deacon restart event for mayor" >&2
  exit 1
fi
if ! grep -q '\[deacon\] mayor is down — restarting' "$TMP_ROOT/deacon.out"; then
  echo "expected operator-visible deacon mayor restart line" >&2
  exit 1
fi
BASH

echo "=== mayor exit receipt logs unexpected exit once ==="
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

eval "$(extract_fn _mayor_exit_receipt)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
EVENT_LOG="$TMP_ROOT/events.log"
DECISION_LOG="$TMP_ROOT/decisions.log"
export SGT_ROOT EVENT_LOG DECISION_LOG

log_event() {
  echo "$*" >> "$EVENT_LOG"
}

_mayor_record_decision() {
  local entry="${1:-}" context="${2:-cycle}" workspace="${3:-}"
  printf '%s|%s|%s\n' "$context" "$workspace" "$entry" >> "$DECISION_LOG"
}

_MAYOR_EXIT_RECEIPT_LOGGED=0
_mayor_exit_receipt 42 EXIT
_mayor_exit_receipt 99 EXIT

if [[ "$(wc -l < "$EVENT_LOG")" -ne 1 ]]; then
  echo "expected mayor exit receipt to log exactly once" >&2
  exit 1
fi
if ! grep -q 'MAYOR_STOP reason_code=nonzero-exit exit_code=42 signal=EXIT unexpected=true' "$EVENT_LOG"; then
  echo "expected unexpected mayor exit receipt with nonzero reason code" >&2
  exit 1
fi
if [[ "$(wc -l < "$DECISION_LOG")" -ne 1 ]]; then
  echo "expected mayor exit receipt to append one decision entry" >&2
  exit 1
fi
if ! grep -q 'mayor-stop-unexpected|'"$SGT_ROOT"'|MAYOR STOP reason_code=nonzero-exit exit_code=42 signal=EXIT unexpected=true' "$DECISION_LOG"; then
  echo "expected durable unexpected-stop decision entry" >&2
  exit 1
fi
BASH

if ! grep -q 'DEACON_RESTART_MAYOR' "$SGT_SCRIPT"; then
  echo "expected mayor restart supervision event in sgt" >&2
  exit 1
fi
if ! grep -q 'MAYOR_STOP reason_code=' "$SGT_SCRIPT"; then
  echo "expected mayor exit receipt instrumentation in sgt" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
