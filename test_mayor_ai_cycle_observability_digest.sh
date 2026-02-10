#!/usr/bin/env bash
# test_mayor_ai_cycle_observability_digest.sh — Deterministic mayor AI observability counter/digest behavior.

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
export SGT_MAYOR_AI_CYCLE_TIMEOUT_SECS=9
export SGT_MAYOR_AI_CYCLE_STATE="$SGT_CONFIG/mayor-ai-cycle.state"
export SGT_MAYOR_AI_OBSERVABILITY_STATE="$SGT_CONFIG/mayor-ai-observability.state"

EVENT_LOG="$TMP_ROOT/events.log"
DECISION_LOG="$TMP_ROOT/decisions.log"

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
  :
}

timeout() {
  local secs="$1"
  shift
  case "${TIMEOUT_MODE:-success}" in
    timeout) return 124 ;;
    error) return 17 ;;
    success) return 0 ;;
    *) return 0 ;;
  esac
}

backend="claude"
workspace="$TMP_ROOT/workspace"
mkdir -p "$workspace"
dispatch_snapshot_file="$TMP_ROOT/dispatch.tsv"
touch "$dispatch_snapshot_file"

for mode in timeout timeout error success; do
  TIMEOUT_MODE="$mode"
  set +e
  _mayor_run_ai_decision_cycle "$backend" "$workspace" "$dispatch_snapshot_file" "trigger-${mode}" "periodic"
  rc=$?
  set -e
  if [[ "$mode" == "success" && "$rc" -ne 0 ]]; then
    echo "expected success mode to return 0" >&2
    exit 1
  fi
  if [[ "$mode" != "success" && "$rc" -eq 0 ]]; then
    echo "expected failure mode to return non-zero for $mode" >&2
    exit 1
  fi
done

if ! grep -q 'MAYOR_AI_CYCLE_DIGEST outcome=fail reason_code=decision-timebox-exceeded totals{i=2,ok=0,fail=2,timeout=2,error=0} streak{fail=2,timeout=2,error=0}' "$EVENT_LOG"; then
  echo "expected repeated timeout digest to expose timeout streak in trail output" >&2
  exit 1
fi
if ! grep -q 'MAYOR_AI_CYCLE_DIGEST outcome=fail reason_code=decision-run-error totals{i=3,ok=0,fail=3,timeout=2,error=1} streak{fail=3,timeout=0,error=1}' "$EVENT_LOG"; then
  echo "expected error digest to increment error total and rotate streak type" >&2
  exit 1
fi
if ! grep -q 'MAYOR_AI_CYCLE_DIGEST outcome=success reason_code=none totals{i=4,ok=1,fail=3,timeout=2,error=1} streak{fail=0,timeout=0,error=0}' "$EVENT_LOG"; then
  echo "expected healthy cycle digest to reset streaks while totals roll forward" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="totalInvocations"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "4" ]]; then
  echo "expected observability state totalInvocations=4" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="totalTimeout"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "2" ]]; then
  echo "expected observability state totalTimeout=2" >&2
  exit 1
fi
if [[ "$(awk -F= '$1=="totalError"{print $2; exit}' "$SGT_MAYOR_AI_OBSERVABILITY_STATE")" != "1" ]]; then
  echo "expected observability state totalError=1" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
