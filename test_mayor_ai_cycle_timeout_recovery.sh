#!/usr/bin/env bash
# test_mayor_ai_cycle_timeout_recovery.sh — Regression checks for mayor AI-cycle timeout fail-closed recovery.

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

eval "$(extract_fn _mayor_ai_cycle_timeout_secs)"
eval "$(extract_fn _mayor_ai_cycle_reason_code_for_exit)"
eval "$(extract_fn _mayor_ai_cycle_observability_state_read)"
eval "$(extract_fn _mayor_ai_cycle_observability_state_write)"
eval "$(extract_fn _mayor_ai_cycle_observability_record)"
eval "$(extract_fn _mayor_ai_cycle_state_write)"
eval "$(extract_fn _mayor_ai_cycle_state_clear)"
eval "$(extract_fn _mayor_run_ai_decision_cycle)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
mkdir -p "$SGT_CONFIG"
export SGT_ROOT SGT_CONFIG
export SGT_MAYOR_AI_CYCLE_STATE="$SGT_CONFIG/mayor-ai-cycle.state"
export SGT_MAYOR_AI_OBSERVABILITY_STATE="$SGT_CONFIG/mayor-ai-observability.state"
export SGT_MAYOR_AI_CYCLE_TIMEOUT_SECS=7

EVENT_LOG="$TMP_ROOT/events.log"
DECISION_LOG="$TMP_ROOT/decisions.log"
TRACE_LOG="$TMP_ROOT/trace.log"
LOCK_RELEASE_LOG="$TMP_ROOT/lock-release.log"

log_event() {
  echo "$*" >> "$EVENT_LOG"
}

_escape_quotes() {
  printf "%s" "${1:-}"
}

_mayor_record_decision() {
  local entry="${1:-}"
  local context="${2:-cycle}"
  printf '%s|%s\n' "$context" "$entry" >> "$DECISION_LOG"
}

_mayor_lock_release() {
  echo "$1" >> "$LOCK_RELEASE_LOG"
}

timeout() {
  local secs="$1"
  shift
  echo "timeout_secs=$secs mode=${TIMEOUT_MODE:-success}" >> "$TRACE_LOG"
  case "${TIMEOUT_MODE:-success}" in
    timeout) return 124 ;;
    success) return 0 ;;
    *) return 17 ;;
  esac
}

backend="claude"
workspace="$TMP_ROOT/workspace"
mkdir -p "$workspace"
dispatch_snapshot_file="$TMP_ROOT/dispatch.tsv"
touch "$dispatch_snapshot_file"

TIMEOUT_MODE=timeout
set +e
_mayor_run_ai_decision_cycle "$backend" "$workspace" "$dispatch_snapshot_file" "trigger-key-1" "merged:pr#10:#9:rig"
timeout_rc=$?
set -e
if [[ "$timeout_rc" -eq 0 ]]; then
  echo "expected timeout cycle to fail closed" >&2
  exit 1
fi
if [[ -f "$SGT_MAYOR_AI_CYCLE_STATE" ]]; then
  echo "expected timeout cycle to clear mayor AI-cycle state file" >&2
  exit 1
fi
if [[ "$(wc -l < "$LOCK_RELEASE_LOG")" -ne 1 ]]; then
  echo "expected exactly one lock release on timeout fail-closed" >&2
  exit 1
fi
if ! grep -q 'MAYOR_AI_CYCLE_FAIL_CLOSED reason_code=decision-timebox-exceeded' "$EVENT_LOG"; then
  echo "expected fail-closed trail event with timeout reason_code" >&2
  exit 1
fi
if ! grep -q 'recovery_hint="inspect AI backend health, then run: sgt wake-mayor \"manual-retry\""' "$EVENT_LOG"; then
  echo "expected fail-closed trail event to include actionable recovery hint" >&2
  exit 1
fi
if ! grep -q 'ai-cycle-fail-closed|MAYOR AI CYCLE FAIL_CLOSED reason_code=decision-timebox-exceeded' "$DECISION_LOG"; then
  echo "expected timeout fail-closed decision-log entry with reason code" >&2
  exit 1
fi
if ! grep -q 'MAYOR_AI_CYCLE_DIGEST outcome=fail reason_code=decision-timebox-exceeded totals{i=1,ok=0,fail=1,timeout=1,error=0} streak{fail=1,timeout=1,error=0}' "$EVENT_LOG"; then
  echo "expected timeout digest trail event with counter increment" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="totalTimeout"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "1" ]]; then
  echo "expected timeout counter to increment to 1 after fail-closed timeout" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="consecutiveTimeout"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "1" ]]; then
  echo "expected consecutive timeout streak to be 1 after timeout cycle" >&2
  exit 1
fi

TIMEOUT_MODE=success
_mayor_run_ai_decision_cycle "$backend" "$workspace" "$dispatch_snapshot_file" "trigger-key-2" "periodic"
if [[ -f "$SGT_MAYOR_AI_CYCLE_STATE" ]]; then
  echo "expected successful cycle to clear mayor AI-cycle state file" >&2
  exit 1
fi
if [[ "$(wc -l < "$LOCK_RELEASE_LOG")" -ne 1 ]]; then
  echo "expected successful follow-up cycle not to force lock release" >&2
  exit 1
fi
if ! grep -q 'MAYOR_AI_CYCLE completed duration=' "$EVENT_LOG"; then
  echo "expected successful cycle completion event after timeout recovery" >&2
  exit 1
fi
if ! grep -q 'MAYOR_AI_CYCLE_DIGEST outcome=success reason_code=none totals{i=2,ok=1,fail=1,timeout=1,error=0} streak{fail=0,timeout=0,error=0}' "$EVENT_LOG"; then
  echo "expected success digest trail event to reset streaks and roll totals forward" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="totalInvocations"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "2" ]]; then
  echo "expected total invocation counter to roll forward to 2" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="totalSuccess"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "1" ]]; then
  echo "expected success counter to increment after healthy cycle" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="totalFail"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "1" ]]; then
  echo "expected fail counter to remain at 1 after healthy cycle" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="totalTimeout"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "1" ]]; then
  echo "expected timeout total to roll forward unchanged after healthy cycle" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="consecutiveTimeout"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "0" ]]; then
  echo "expected healthy cycle to reset consecutive timeout streak" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="consecutiveFail"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "0" ]]; then
  echo "expected healthy cycle to reset consecutive fail streak" >&2
  exit 1
fi

if [[ "$(grep -c 'timeout_secs=7 mode=' "$TRACE_LOG")" -ne 2 ]]; then
  echo "expected timeout wrapper to be invoked with configured timeout for both cycles" >&2
  exit 1
fi
BASH

if ! grep -q 'SGT_MAYOR_AI_CYCLE_TIMEOUT_SECS' "$SGT_SCRIPT"; then
  echo "expected mayor AI-cycle timeout environment variable to be defined" >&2
  exit 1
fi

if ! grep -q 'MAYOR_AI_CYCLE_FAIL_CLOSED reason_code=' "$SGT_SCRIPT"; then
  echo "expected mayor AI-cycle fail-closed event instrumentation" >&2
  exit 1
fi
if ! grep -q 'MAYOR_AI_CYCLE_DIGEST' "$SGT_SCRIPT"; then
  echo "expected mayor AI-cycle digest trail instrumentation" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
