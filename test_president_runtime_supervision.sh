#!/usr/bin/env bash
# test_president_runtime_supervision.sh — Verify President runtime supervision and bounded rig-local intervention.

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

eval "$(extract_fn _president_session_name)"
eval "$(extract_fn _president_runtime_dir)"
eval "$(extract_fn _president_heartbeat_file)"
eval "$(extract_fn _president_heartbeat_stale_secs)"
eval "$(extract_fn _president_heartbeat_snapshot)"
eval "$(extract_fn _president_heartbeat_health)"
eval "$(extract_fn _president_exit_state_file)"
eval "$(extract_fn _president_exit_state_read)"
eval "$(extract_fn _president_exit_state_write)"
eval "$(extract_fn _president_intervention_state_file)"
eval "$(extract_fn _president_intervention_state_read)"
eval "$(extract_fn _president_intervention_state_write)"
eval "$(extract_fn _president_operator_events_file)"
eval "$(extract_fn _president_operator_event_state_append)"
eval "$(extract_fn _president_operator_event_rows)"
eval "$(extract_fn _president_intervention_allowed)"
eval "$(extract_fn _president_operator_event_kind)"
eval "$(extract_fn _president_operator_event_severity)"
eval "$(extract_fn _president_operator_notify_enabled)"
eval "$(extract_fn _president_operator_dedupe_key)"
eval "$(extract_fn _president_operator_overlap_key)"
eval "$(extract_fn _president_operator_log_event)"
eval "$(extract_fn _plan_state_path)"
eval "$(extract_fn _plan_pending_underfill_target)"
eval "$(extract_fn _mayor_rig_hibernated)"
eval "$(extract_fn _deacon_supervise_president)"
eval "$(extract_fn _president_supervise_rig_mayor)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_PLAN_STATE_DIR="$SGT_CONFIG/plan-state"
mkdir -p "$SGT_CONFIG/president" "$SGT_CONFIG/mayors/demo" "$SGT_PLAN_STATE_DIR"
EVENT_LOG="$TMP_ROOT/events.log"
EVENT_STATE="$SGT_CONFIG/president/president-operator-events.tsv"
START_LOG="$TMP_ROOT/start.log"
REFRESH_LOG="$TMP_ROOT/refresh.log"
WAKE_LOG="$TMP_ROOT/wake.log"
export SGT_ROOT SGT_CONFIG SGT_PLAN_STATE_DIR EVENT_LOG EVENT_STATE START_LOG REFRESH_LOG WAKE_LOG
export SGT_PRESIDENT_INTERVAL=60
export SGT_PRESIDENT_INTERVENTION_STALE_SECS=900
export SGT_PRESIDENT_INTERVENTION_COOLDOWN_SECS=600
TEST_HIBERNATED=0

log_event() {
  echo "$*" >> "$EVENT_LOG"
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

cmd_president_start() {
  echo "started" >> "$START_LOG"
}

cmd_mayor_start() {
  echo "mayor-start:$1" >> "$START_LOG"
}

cmd_mayor_refresh() {
  echo "$1" >> "$REFRESH_LOG"
}

cmd_wake_mayor() {
  echo "$1" >> "$WAKE_LOG"
}

_mayor_scope_apply() {
  SGT_MAYOR_SCOPE_RIG="${1:-}"
}

_mayor_scope_session_name() {
  printf 'sgt-mayor-%s\n' "${1:-${SGT_MAYOR_SCOPE_RIG:-}}"
}

_mayor_heartbeat_stale_secs() {
  echo 720
}

_mayor_heartbeat_snapshot() {
  printf '30|2026-03-31T00:00:00Z|ok|123|cycle-complete|7|periodic\n'
}

_mayor_heartbeat_health() {
  echo healthy
}

_mayor_rig_activity_enabled() {
  return 0
}

_mayor_rig_activity_snapshot() {
  printf 'active|open_issues=1 open_prs=0 active_polecats=0 merge_queue=0 pending_plan_requests=0|1|0|0|0|0|tasks-exhausted-awaiting-acceptance|pending\n'
}

_mayor_rig_activity_state_read() {
  printf 'active|open_issues=1|2026-03-31T00:00:00Z|1774915200|none|2026-03-31T00:00:00Z|1774915200|plan-pending|2026-03-31T00:00:00Z|periodic\n'
}

_mayor_rig_hibernation_mode() {
  if [[ "${TEST_HIBERNATED:-0}" == "1" ]]; then
    echo "manual"
  else
    echo "none"
  fi
}

_ralph_mode_snapshot_fields() {
  printf '0||||0|disabled|Ralph mode disabled|0|0|0|0|0|0|0||||\n'
}

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" ]]; then
    case "${3:-}" in
      sgt-president) return 1 ;;
      sgt-mayor-demo) return 0 ;;
    esac
  fi
  return 0
}

_president_exit_state_write "nonzero-exit" "9" "EXIT" "true"
_deacon_supervise_president > "$TMP_ROOT/deacon.out"

if [[ "$(wc -l < "$START_LOG")" -ne 1 ]]; then
  echo "expected deacon supervision to restart president once" >&2
  exit 1
fi
if ! grep -q 'DEACON_RESTART_PRESIDENT reason=session-missing' "$EVENT_LOG"; then
  echo "expected deacon restart event for president" >&2
  exit 1
fi
if ! grep -q 'last_exit=nonzero-exit signal=EXIT code=9' "$TMP_ROOT/deacon.out"; then
  echo "expected operator-visible president restart line to include exit telemetry" >&2
  exit 1
fi

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" && "${3:-}" == "sgt-mayor-demo" ]]; then
    return 0
  fi
  return 1
}

_president_supervise_rig_mayor demo periodic > "$TMP_ROOT/president.out"

grep -qx 'demo' "$REFRESH_LOG" || {
  echo "expected president to refresh the stuck rig-local mayor" >&2
  exit 1
}
if ! grep -q 'PRESIDENT_INTERVENTION rig=demo action=refresh reason=actionable-no-forward-motion' "$EVENT_LOG"; then
  echo "expected durable president intervention event for stuck rig" >&2
  exit 1
fi
if ! grep -q 'PRESIDENT_OPERATOR_EVENT rig=demo kind=stalled-purpose severity=warning notify=1 dedupe_key=president:demo:stalled-purpose:actionable-no-forward-motion:refresh overlap_key=rig-incident:demo:actionable-no-forward-motion action=refresh reason=actionable-no-forward-motion outcome=intervened' "$EVENT_LOG"; then
  echo "expected structured President operator event for stalled-purpose intervention" >&2
  exit 1
fi
if ! grep -q $'\tdemo\tstalled-purpose\twarning\t1\t' "$EVENT_STATE"; then
  echo "expected structured president operator event history state for stalled-purpose intervention" >&2
  exit 1
fi
if [[ -s "$WAKE_LOG" ]]; then
  echo "expected refresh intervention instead of plain wake for stale rig" >&2
  exit 1
fi

_ralph_mode_snapshot_fields() {
  printf '1|1K PNL for 5m btc pipeline|unmet|3|0|underfilled|condition unmet; active_lanes=1 target=3|1|3|2|0|0|1|1||||\n'
}

_president_supervise_rig_mayor demo periodic > "$TMP_ROOT/president-ralph-underfilled.out"

grep -qx 'president:demo:ralph-underfilled' "$WAKE_LOG" || {
  echo "expected President to wake mayor for Ralph underfill when admissible backlog exists" >&2
  exit 1
}
if ! grep -q 'PRESIDENT_INTERVENTION rig=demo action=wake reason=ralph-underfilled' "$EVENT_LOG"; then
  echo "expected durable President wake intervention for Ralph underfill" >&2
  exit 1
fi
if ! grep -q 'PRESIDENT_OPERATOR_EVENT rig=demo kind=drift severity=warning notify=1 dedupe_key=president:demo:drift:ralph-underfilled:wake overlap_key=rig-incident:demo:ralph action=wake reason=ralph-underfilled outcome=intervened' "$EVENT_LOG"; then
  echo "expected structured President drift event for Ralph refill wake" >&2
  exit 1
fi

_ralph_mode_snapshot_fields() {
  printf '1|1K PNL for 5m btc pipeline|unmet|3|0|underfilled|condition unmet; active_lanes=1 target=3|1|1|0|0|0|1|1||||\n'
}

_president_supervise_rig_mayor demo periodic > "$TMP_ROOT/president-ralph-contradiction.out"

if [[ "$(grep -cx 'demo' "$REFRESH_LOG")" -ne 2 ]]; then
  echo "expected Ralph contradiction to trigger a refresh intervention" >&2
  exit 1
fi
if ! grep -q 'PRESIDENT_INTERVENTION rig=demo action=refresh reason=ralph-contradiction' "$EVENT_LOG"; then
  echo "expected durable President contradiction intervention for unrefillable Ralph state" >&2
  exit 1
fi
if ! grep -q 'PRESIDENT_OPERATOR_EVENT rig=demo kind=contradiction severity=warning notify=1 dedupe_key=president:demo:contradiction:ralph-contradiction:refresh overlap_key=rig-incident:demo:ralph action=refresh reason=ralph-contradiction outcome=intervened' "$EVENT_LOG"; then
  echo "expected structured President contradiction event for unrefillable Ralph state" >&2
  exit 1
fi

_ralph_mode_snapshot_fields() {
  printf '0||||0|disabled|Ralph mode disabled|0|0|0|0|0|0|0||||\n'
}

cat > "$SGT_PLAN_STATE_DIR/demo.json" <<'JSON'
{
  "policy": {
    "max_in_flight": 2
  },
  "completion": {
    "status": "pending",
    "rollup": "tasks-exhausted-awaiting-acceptance"
  }
}
JSON

_mayor_rig_activity_snapshot() {
  printf 'active|pending-plan-underfilled target=2 active_polecats=0 open_issues=0 open_prs=0 merge_queue=0|0|0|0|0|0|tasks-exhausted-awaiting-acceptance|pending\n'
}

refresh_count_before_pending_plan="$(grep -c '^demo$' "$REFRESH_LOG" || true)"
_president_supervise_rig_mayor demo periodic > "$TMP_ROOT/president-plan-underfill.out"

if [[ "$(grep -cx 'demo' "$REFRESH_LOG")" -ne $((refresh_count_before_pending_plan + 1)) ]]; then
  echo "expected president to refresh again for pending plan underfill" >&2
  exit 1
fi
if ! grep -q 'PRESIDENT_INTERVENTION rig=demo action=refresh reason=pending-plan-underfilled' "$EVENT_LOG"; then
  echo "expected durable president intervention event for pending plan underfill" >&2
  exit 1
fi
if ! grep -q 'PRESIDENT_OPERATOR_EVENT rig=demo kind=stalled-purpose severity=warning notify=1 dedupe_key=president:demo:stalled-purpose:pending-plan-underfilled:refresh overlap_key=rig-incident:demo:pending-plan-underfill action=refresh reason=pending-plan-underfilled outcome=intervened' "$EVENT_LOG"; then
  echo "expected structured President operator event for pending plan underfill" >&2
  exit 1
fi

rm -f "$SGT_PLAN_STATE_DIR/demo.json"

_mayor_rig_activity_snapshot() {
  printf 'active|open_issues=1 open_prs=0 active_polecats=0 merge_queue=0 pending_plan_requests=0|1|0|0|0|0|tasks-exhausted-awaiting-acceptance|pending\n'
}

_mayor_rig_activity_state_read() {
  local now recent wake_recent
  now="$(date +%s)"
  recent=$((now - 60))
  wake_recent=$((now - 30))
  printf 'active|open_issues=1|2026-03-31T00:00:00Z|1774915200|none|recent|%s|recent-progress|wake-recent|%s|manual\n' "$recent" "$wake_recent"
}

_president_supervise_rig_mayor demo manual > "$TMP_ROOT/president-wake.out"

grep -qx 'president:demo:actionable-rig-recheck' "$WAKE_LOG" || {
  echo "expected President to use a quiet wake for recent actionable rig activity" >&2
  exit 1
}
if ! grep -q 'PRESIDENT_OPERATOR_EVENT rig=demo kind=intervention severity=info notify=0 dedupe_key=president:demo:intervention:actionable-rig-recheck:wake overlap_key=rig-incident:demo:actionable-no-forward-motion action=wake reason=actionable-rig-recheck outcome=intervened' "$EVENT_LOG"; then
  echo "expected quiet President operator event for actionable rig recheck" >&2
  exit 1
fi

_president_supervise_rig_mayor demo manual >/dev/null || true
if ! grep -q 'PRESIDENT_OPERATOR_EVENT rig=demo kind=intervention severity=info notify=0 dedupe_key=president:demo:intervention:actionable-rig-recheck:wake overlap_key=rig-incident:demo:actionable-no-forward-motion action=wake reason=actionable-rig-recheck outcome=suppressed-by-cooldown' "$EVENT_LOG"; then
  echo "expected President operator event to record cooldown suppression instead of replaying the same wake" >&2
  exit 1
fi
if [[ "$(wc -l < "$EVENT_STATE")" -lt 3 ]]; then
  echo "expected president operator event history to retain intervened and suppressed entries" >&2
  exit 1
fi

TEST_HIBERNATED=1
refresh_count_before_hibernated="$(grep -c '^demo$' "$REFRESH_LOG" || true)"
wake_count_before_hibernated="$(grep -c '^president:demo:actionable-rig-recheck$' "$WAKE_LOG" || true)"
event_count_before_hibernated="$(grep -c '^PRESIDENT_INTERVENTION rig=demo ' "$EVENT_LOG" || true)"

_mayor_rig_activity_state_read() {
  printf 'hibernated|open_issues=1|2026-03-31T00:00:00Z|1774915200|manual|2026-03-31T00:00:00Z|1774915200|plan-pending|2026-03-31T00:00:00Z|manual-stop\n'
}

_president_supervise_rig_mayor demo manual >/dev/null || true

if [[ "$(grep -c '^demo$' "$REFRESH_LOG" || true)" -ne "$refresh_count_before_hibernated" ]]; then
  echo "expected hibernated rig to skip President refresh intervention" >&2
  exit 1
fi
if [[ "$(grep -c '^president:demo:actionable-rig-recheck$' "$WAKE_LOG" || true)" -ne "$wake_count_before_hibernated" ]]; then
  echo "expected hibernated rig to skip President wake recheck intervention" >&2
  exit 1
fi
if [[ "$(grep -c '^PRESIDENT_INTERVENTION rig=demo ' "$EVENT_LOG" || true)" -ne "$event_count_before_hibernated" ]]; then
  echo "expected hibernated rig to avoid logging new President interventions" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
