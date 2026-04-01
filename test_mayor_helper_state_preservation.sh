#!/usr/bin/env bash
# test_mayor_helper_state_preservation.sh — Mayor helper calls must preserve rig scope and shell error mode.

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

eval "$(extract_fn _shell_errexit_state)"
eval "$(extract_fn _shell_errexit_restore)"
eval "$(extract_fn _mayor_scope_session_name)"
eval "$(extract_fn _mayor_scope_dir)"
eval "$(extract_fn _mayor_scope_apply)"
eval "$(extract_fn _mayor_target_rigs_for_reason)"
eval "$(extract_fn _wake_mayor)"
eval "$(extract_fn _mayor_architecture_per_rig)"
eval "$(extract_fn _cmd_mayor_start_one)"
eval "$(extract_fn cmd_mayor_start)"
eval "$(extract_fn _cmd_mayor_stop_one)"
eval "$(extract_fn cmd_mayor_stop)"
eval "$(extract_fn _cmd_mayor_refresh_one)"
eval "$(extract_fn cmd_mayor_refresh)"
eval "$(extract_fn cmd_wake_mayor)"
eval "$(extract_fn _president_supervise_rig_mayor)"
eval "$(extract_fn cmd_status_json)"
eval "$(extract_fn _cmd_status_human)"
eval "$(extract_fn _mayor_notify_rigger)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_RIGS="$SGT_CONFIG/rigs"
SGT_POLECATS="$SGT_CONFIG/polecats"
SGT_AGENTS="$SGT_CONFIG/agents"
SGT_DAEMON_PID="$SGT_CONFIG/daemon.pid"
SGT_LOG="$TMP_ROOT/events.log"
mkdir -p "$SGT_CONFIG" "$SGT_RIGS" "$SGT_POLECATS" "$SGT_AGENTS"
printf 'demo-repo\n' > "$SGT_RIGS/demo"
printf 'beta-repo\n' > "$SGT_RIGS/beta"
export SGT_ROOT SGT_CONFIG SGT_RIGS SGT_POLECATS SGT_AGENTS SGT_DAEMON_PID SGT_LOG TMP_ROOT
SGT_MAYOR_ARCHITECTURE="per-rig"
SGT_MAYOR_INTERVAL="60"
export SGT_MAYOR_ARCHITECTURE SGT_MAYOR_INTERVAL

ensure_init() { :; }
die() { echo "${1:-die}" >&2; exit 1; }
info() { :; }
warn() { :; }
_json_quote() { printf '"%s"' "${1:-}"; }
_json_print_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    if [[ "$first" -eq 0 ]]; then
      printf ','
    fi
    first=0
    printf '%s' "$item"
  done
  printf ']'
}
_section() { :; }
_status_badge() { printf '%s' "${1:-}"; }
_dim() { :; }
_reset() { :; }
_fg_gray() { :; }
_fg_yellow() { :; }
_term_cols() { echo 80; }
_status_pr_title_cols() { echo 40; }
_deacon_heartbeat_stale_secs() { echo 300; }
_deacon_heartbeat_snapshot() { printf '0|2026-04-01T00:00:00Z|ok\n'; }
_deacon_heartbeat_health() { echo healthy; }
_president_enabled() { return 0; }
_president_session_name() { echo sgt-president; }
_president_heartbeat_stale_secs() { echo 300; }
_president_heartbeat_snapshot() { printf '0|2026-04-01T00:00:00Z|ok|123|cycle-complete|1|periodic\n'; }
_president_heartbeat_health() { echo healthy; }
_president_exit_state_read() { printf '|||||\n'; }
_president_operator_events_json() { printf '[]\n'; }
_president_operator_events_human() { :; }
_mayor_rig_activity_enabled() { return 1; }
_mayor_architecture_per_rig() { return 0; }
_mayor_all_rigs() { printf 'demo\nbeta\n'; }
_mayor_wake_reason_rig() { return 1; }
_mayor_lock_snapshot() { printf 'none|||\n'; }
_mayor_heartbeat_stale_secs() { echo 720; }
_mayor_heartbeat_snapshot() { printf '0|2026-04-01T00:00:00Z|ok|321|startup|0|startup\n'; }
_mayor_heartbeat_health() { echo healthy; }
_mayor_start_failure_state_read() { printf '|||||\n'; }
_mayor_exit_state_read() { printf '|||||||||\n'; }
_mayor_decision_log_failure_state_read() { printf '||||\n'; }
_mayor_notify_alert_state_read() { printf '|||||||||\n'; }
_mayor_prompt_budget_state_read() { printf '|||||||\n'; }
_mayor_auto_refresh_state_read() { printf '|||||||||\n'; }
_mayor_review_watchdog_status_snapshot() { printf '0|0|900\n'; }
_merge_queue_count_for_rig() { echo 0; }
_merge_queue_oldest_age_for_rig() { echo 0; }
_polecat_runtime_json() { printf '{}'; }
_agent_heartbeat_stale_secs() { echo 180; }
_agent_heartbeat_snapshot() { printf '0|2026-04-01T00:00:00Z|ok\n'; }
_mayor_scope_agent_name() { printf 'mayor/%s\n' "${1:-${SGT_MAYOR_SCOPE_RIG:-}}"; }
_hierarchy_cutover_retire_shared_mayor() { :; }
_openclaw_notify_config_read() { printf 'main\nlast\n\n\n'; }
_rig_notify_agent_read() { return 1; }
_mayor_notify_result_set() { :; }
_mayor_notify_message_key() { printf 'key\n'; }
_mayor_notify_attempt_state_file() { printf '%s/notify.state\n' "$TMP_ROOT"; }
_mayor_notify_state_load() { return 1; }
_mayor_notify_state_write() { :; }
_mayor_notify_receipt_record() { _MAYOR_NOTIFY_RECEIPT_VERIFIED_AT="2026-04-01T00:00:00Z"; }
_mayor_notify_classify_receipt() {
  _MAYOR_NOTIFY_CLASSIFY_OUTCOME="delivered"
  _MAYOR_NOTIFY_CLASSIFY_REASON="ack-verified"
  _MAYOR_NOTIFY_CLASSIFY_MATCHER="transport-exit-zero"
}
_mayor_notify_decision_outcome() { printf 'delivered\n'; }
_mayor_record_decision() { :; }
_one_line() { printf '%s' "${1:-}"; }
log_event() { :; }
_escape_quotes() { printf '%s' "${1:-}"; }
_sgt_exec_path() { printf '%s/fake-sgt\n' "$TMP_ROOT"; }
_mayor_start_log_file() { printf '%s/mayor-start.log\n' "$TMP_ROOT"; }
_mayor_start_validation_timeout_secs() { echo 1; }
_mayor_wait_for_start() { return 0; }
_mayor_start_failure_state_write() { :; }
_mayor_exit_state_write() { :; }
_mayor_refresh_token() { printf 'refresh-token\n'; }
_mayor_refresh_handoffs_dir() { printf '%s/handoffs\n' "$TMP_ROOT"; }
_mayor_dispatch_snapshot_file() { :; }
_mayor_build_briefing() { :; }
_mayor_refresh_archive_transients() { :; }
_mayor_refresh_write_handoff() { :; }
_president_intervention_allowed() { return 0; }
_president_operator_log_event() { :; }
_president_intervention_state_write() { :; }
_mayor_rig_activity_snapshot() { printf 'active|steady|0|0|0|0|0|tasks-in-progress|pending\n'; }
_mayor_rig_activity_state_read() { printf 'active|steady|2026-04-01T00:00:00Z|0|none|2026-04-01T00:00:00Z|0|steady|2026-04-01T00:00:00Z|manual\n'; }
rig_repo() { printf 'demo-repo\n'; }
_ralph_mode_snapshot_fields() { printf '0||||||0|0|0|0|0|0|0||||\n'; }
_plan_pending_underfill_target() { echo 0; }
cmd_mayor_start_called=0
cmd_mayor_refresh_called=0
cmd_wake_mayor_called=0
tmux() {
  if [[ "${1:-}" == "has-session" ]]; then
    return 1
  fi
  return 0
}
mkfifo() {
  if [[ -p "${1:-}" ]]; then
    return 0
  fi
  command mkfifo "$@"
}
openclaw() { printf '{}\n'; }

_mayor_scope_apply "demo"
original_scope="${SGT_MAYOR_SCOPE_RIG:-}"
original_lock="${SGT_MAYOR_LOCK:-}"
cmd_status_json >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "$original_scope" || "${SGT_MAYOR_LOCK:-}" != "$original_lock" ]]; then
  echo "expected cmd_status_json to preserve per-rig mayor scope" >&2
  exit 1
fi

_cmd_status_human >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "$original_scope" || "${SGT_MAYOR_LOCK:-}" != "$original_lock" ]]; then
  echo "expected _cmd_status_human to preserve per-rig mayor scope" >&2
  exit 1
fi

set +e
before_flags="$-"
_mayor_notify_rigger "hello from mayor" 1 demo >/dev/null
after_flags="$-"
if [[ "$before_flags" == *e* || "$after_flags" == *e* ]]; then
  echo "expected _mayor_notify_rigger to preserve disabled errexit in mayor loop" >&2
  exit 1
fi

_mayor_scope_apply "demo"
mkdir -p "$(dirname "$SGT_MAYOR_FIFO")"
touch "$SGT_MAYOR_FIFO"
_wake_mayor "broadcast" >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "demo" ]]; then
  echo "expected _wake_mayor to preserve caller scope after per-rig routing" >&2
  exit 1
fi

_mayor_scope_apply "outer"
cmd_mayor_start "demo" >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "outer" ]]; then
  echo "expected cmd_mayor_start to preserve caller scope" >&2
  exit 1
fi

_mayor_scope_apply "outer"
cmd_mayor_stop "demo" >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "outer" ]]; then
  echo "expected cmd_mayor_stop to preserve caller scope" >&2
  exit 1
fi

_mayor_scope_apply "outer"
cmd_mayor_refresh "demo" >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "outer" ]]; then
  echo "expected cmd_mayor_refresh to preserve caller scope" >&2
  exit 1
fi

_mayor_scope_apply "outer"
_cmd_mayor_start_one "demo" >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "outer" ]]; then
  echo "expected _cmd_mayor_start_one to preserve caller scope" >&2
  exit 1
fi

_mayor_scope_apply "outer"
_cmd_mayor_stop_one "demo" >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "outer" ]]; then
  echo "expected _cmd_mayor_stop_one to preserve caller scope" >&2
  exit 1
fi

_mayor_scope_apply "outer"
_cmd_mayor_refresh_one "demo" >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "outer" ]]; then
  echo "expected _cmd_mayor_refresh_one to preserve caller scope" >&2
  exit 1
fi

_mayor_scope_apply "outer"
_president_supervise_rig_mayor "demo" "startup" >/dev/null
if [[ "${SGT_MAYOR_SCOPE_RIG:-}" != "outer" ]]; then
  echo "expected _president_supervise_rig_mayor to preserve caller scope" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
