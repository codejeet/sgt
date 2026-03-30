#!/usr/bin/env bash
# test_mayor_auto_refresh_runtime.sh — Verify Mayor runtime effective-context auto-refresh telemetry and cooldown behavior.

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

for fn in \
  _mayor_refresh_handoffs_dir \
  _mayor_effective_context_state_file \
  _mayor_effective_context_threshold_tokens \
  _mayor_effective_context_cooldown_secs \
  _mayor_effective_context_state_read \
  _mayor_effective_context_state_write \
  _mayor_effective_context_measure_file \
  _mayor_refresh_token \
  _mayor_refresh_archive_transients \
  _mayor_refresh_write_handoff \
  _mayor_auto_refresh_for_prompt; do
  eval "$(extract_fn "$fn")"
done

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export SGT_ROOT="$TMP_ROOT/root"
export SGT_LOG="$TMP_ROOT/events.log"
export SGT_MAYOR_AUTO_REFRESH_THRESHOLD_TOKENS=10
export SGT_MAYOR_AUTO_REFRESH_COOLDOWN_SECS=3600
mkdir -p "$SGT_ROOT/.sgt/mayor-workspace"

_mayor_scope_dir() {
  echo "$SGT_ROOT/.sgt"
}

_mayor_scope_display_text() {
  echo "shared mayor"
}

_mayor_architecture() {
  echo "shared"
}

_mayor_scope_apply() {
  :
}

_mayor_dispatch_snapshot_file() {
  local path="${1:?}"
  printf 'snapshot\n' > "$path"
}

_mayor_start_failure_state_read() {
  printf '||||\n'
}

_mayor_exit_state_read() {
  printf '||||||||\n'
}

_mayor_last_cycle_state_read() {
  printf '||||\n'
}

_mayor_heartbeat_snapshot() {
  printf '0|2026-03-30T00:00:00Z|ok|123|cycle|7|periodic\n'
}

_escape_quotes() {
  printf '%s' "${1:-}"
}

_escape_wake_value() {
  printf '%s' "${1:-}"
}

cmd_status() {
  printf 'mock status\n'
}

log_event() {
  printf '%s\n' "$*" >> "$SGT_LOG"
}

_mayor_record_decision() {
  printf '%s\n' "$1" >> "$TMP_ROOT/decisions.log"
}

_sgt_exec_path() {
  echo /bin/true
}

RESTART_LOG="$TMP_ROOT/restart.log"
_mayor_schedule_restart_after_refresh() {
  printf '%s|%s\n' "${1:-}" "${2:-}" >> "$RESTART_LOG"
}

printf 'briefing\n' > "$SGT_ROOT/.sgt/mayor-briefing.md"
printf 'running\n' > "$SGT_ROOT/.sgt/mayor-ai-cycle.state"
printf 'workspace note\n' > "$SGT_ROOT/.sgt/mayor-workspace/CLAUDE.md"

PROMPT_SMALL="$TMP_ROOT/prompt-small.md"
printf 'tiny prompt\n' > "$PROMPT_SMALL"
out="$(_mayor_auto_refresh_for_prompt "$PROMPT_SMALL" "periodic")"
IFS='|' read -r status decision threshold measured_tokens measured_chars handoff <<< "$out"
[[ "$status" == "continue" ]] || { echo "expected continue status below threshold" >&2; exit 1; }
[[ "$decision" == "below-threshold" ]] || { echo "expected below-threshold decision" >&2; exit 1; }
[[ -z "$handoff" ]] || { echo "expected no handoff below threshold" >&2; exit 1; }

IFS='|' read -r _ _ state_threshold state_measured_tokens _ _ state_fired state_decision _ _ _ <<< "$(_mayor_effective_context_state_read)"
[[ "$state_threshold" == "10" ]] || { echo "expected threshold recorded in state" >&2; exit 1; }
[[ "$state_fired" == "false" ]] || { echo "expected no auto refresh below threshold" >&2; exit 1; }
[[ "$state_decision" == "below-threshold" ]] || { echo "expected below-threshold state decision" >&2; exit 1; }
[[ "$state_measured_tokens" =~ ^[0-9]+$ ]] || { echo "expected measured tokens in state" >&2; exit 1; }

PROMPT_LARGE="$TMP_ROOT/prompt-large.md"
python3 - <<'PY' > "$PROMPT_LARGE"
print("X" * 80)
PY
out="$(_mayor_auto_refresh_for_prompt "$PROMPT_LARGE" "periodic")"
IFS='|' read -r status decision threshold measured_tokens measured_chars handoff <<< "$out"
[[ "$status" == "refreshed" ]] || { echo "expected refreshed status above threshold" >&2; exit 1; }
[[ "$decision" == "auto-refreshed" ]] || { echo "expected auto-refreshed decision" >&2; exit 1; }
[[ -f "$handoff" ]] || { echo "expected handoff file after auto refresh" >&2; exit 1; }
[[ -f "$(dirname "$handoff")/mayor-briefing.md" ]] || { echo "expected archived briefing in handoff" >&2; exit 1; }
[[ -f "$(dirname "$handoff")/mayor-workspace/CLAUDE.md" ]] || { echo "expected archived mayor workspace prompt in handoff" >&2; exit 1; }
grep -q 'refresh_kind: auto-threshold' "$handoff" || { echo "expected auto refresh kind in handoff" >&2; exit 1; }
grep -q 'effective_context_tokens=' "$handoff" || { echo "expected context telemetry in handoff" >&2; exit 1; }
[[ -s "$RESTART_LOG" ]] || { echo "expected restart scheduling after auto refresh" >&2; exit 1; }

IFS='|' read -r _ _ _ _ _ _ state_fired state_decision state_handoff cooldown_ts cooldown_iso <<< "$(_mayor_effective_context_state_read)"
[[ "$state_fired" == "true" ]] || { echo "expected fired=true after auto refresh" >&2; exit 1; }
[[ "$state_decision" == "auto-refreshed" ]] || { echo "expected auto-refreshed state decision" >&2; exit 1; }
[[ "$state_handoff" == "$handoff" ]] || { echo "expected handoff path persisted in state" >&2; exit 1; }
[[ "$cooldown_ts" =~ ^[0-9]+$ ]] || { echo "expected cooldown timestamp in state" >&2; exit 1; }
[[ -n "$cooldown_iso" ]] || { echo "expected cooldown iso timestamp in state" >&2; exit 1; }
grep -q 'MAYOR_EFFECTIVE_CONTEXT threshold_tokens=10' "$SGT_LOG" || { echo "expected effective-context telemetry log" >&2; exit 1; }
grep -q 'fired=true decision=auto-refreshed' "$SGT_LOG" || { echo "expected fired=true telemetry log" >&2; exit 1; }

mkdir -p "$SGT_ROOT/.sgt/mayor-workspace"
printf 'second cycle note\n' > "$SGT_ROOT/.sgt/mayor-workspace/CLAUDE.md"
printf 'briefing again\n' > "$SGT_ROOT/.sgt/mayor-briefing.md"
out="$(_mayor_auto_refresh_for_prompt "$PROMPT_LARGE" "periodic")"
IFS='|' read -r status decision threshold measured_tokens measured_chars handoff_after <<< "$out"
[[ "$status" == "continue" ]] || { echo "expected continue status during cooldown suppression" >&2; exit 1; }
[[ "$decision" == "cooldown-suppressed" ]] || { echo "expected cooldown-suppressed decision" >&2; exit 1; }
[[ "$handoff_after" == "$handoff" ]] || { echo "expected cooldown suppression to retain prior handoff path" >&2; exit 1; }
grep -q 'fired=false decision=cooldown-suppressed' "$SGT_LOG" || { echo "expected cooldown suppression telemetry log" >&2; exit 1; }
BASH

echo "ALL TESTS PASSED"
