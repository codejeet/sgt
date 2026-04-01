#!/usr/bin/env bash
# test_mayor_notify_fail_open_runtime.sh — Mayor notify helper must fail open inside set -e callers.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

bash -s "$SGT_SCRIPT" "$TMP_ROOT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
TMP_ROOT="$2"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _escape_wake_value)"
eval "$(extract_fn log_event)"
eval "$(extract_fn _one_line)"
eval "$(extract_fn _mayor_notify_alert_state_write)"
eval "$(extract_fn _mayor_notify_alert_state_clear)"
eval "$(extract_fn _mayor_notify_rigger_fail_open)"

SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_LOG="$SGT_ROOT/sgt.log"
SGT_MAYOR_NOTIFY_ALERT_STATE="$SGT_CONFIG/mayor-notify-alert.state"
mkdir -p "$SGT_CONFIG"
: > "$SGT_LOG"

_mayor_notify_rigger() {
  _MAYOR_NOTIFY_RESULT_CHANNEL="current"
  _MAYOR_NOTIFY_RESULT_TARGET="channel=current"
  _MAYOR_NOTIFY_RESULT_MESSAGE_KEY="notify-deadbeef"
  _MAYOR_NOTIFY_RESULT_ATTEMPT="1"
  _MAYOR_NOTIFY_RESULT_OUTCOME="transport-failure"
  _MAYOR_NOTIFY_RESULT_REASON="transport-hard-failure"
  _MAYOR_NOTIFY_RESULT_MATCHER="hard-transport-pattern"
  _MAYOR_NOTIFY_RESULT_ESCALATED="1"
  return 1
}

_mayor_notify_rigger_fail_open "wake summary for failed transport" "0" "pmkb"
printf 'still-running\n' > "$TMP_ROOT/continued.out"
BASH

grep -qx 'still-running' "$TMP_ROOT/continued.out" || {
  echo "expected fail-open helper to preserve execution under set -e" >&2
  exit 1
}

ALERT_STATE="$TMP_ROOT/root/.sgt/mayor-notify-alert.state"
[[ -f "$ALERT_STATE" ]] || {
  echo "expected fail-open helper to persist notify alert state" >&2
  exit 1
}
grep -q 'current|channel=current|notify-deadbeef|1|transport-failure|transport-hard-failure|hard-transport-pattern|true' "$ALERT_STATE" || {
  echo "expected fail-open alert state to preserve transport failure details" >&2
  exit 1
}

grep -q 'MAYOR_NOTIFY_FAIL_OPEN channel=current target="channel=current" message_key=notify-deadbeef attempt=1 outcome=transport-failure reason=transport-hard-failure matcher=hard-transport-pattern escalated=1 action=retain-warning-continue' "$TMP_ROOT/root/sgt.log" || {
  echo "expected fail-open helper to emit durable MAYOR_NOTIFY_FAIL_OPEN telemetry" >&2
  exit 1
}

grep -q '_mayor_notify_rigger_fail_open "\$notify_rigger" "0" "\${SGT_MAYOR_SCOPE_RIG:-}"' "$SGT_SCRIPT" || {
  echo "expected mayor cycle to use the fail-open notify helper" >&2
  exit 1
}

echo "ALL TESTS PASSED"
