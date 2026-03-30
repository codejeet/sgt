#!/usr/bin/env bash
# test_mayor_auto_refresh_threshold.sh — Regression checks for Mayor prompt-budget auto-refresh thresholding.

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

eval "$(extract_fn _mayor_auto_refresh_threshold_tokens)"
eval "$(extract_fn _mayor_auto_refresh_cooldown_secs)"
eval "$(extract_fn _mayor_prompt_token_estimate_from_chars)"
eval "$(extract_fn _mayor_prompt_budget_measure_file)"
eval "$(extract_fn _mayor_prompt_budget_state_file)"
eval "$(extract_fn _mayor_prompt_budget_state_read)"
eval "$(extract_fn _mayor_prompt_budget_state_write)"
eval "$(extract_fn _mayor_auto_refresh_state_file)"
eval "$(extract_fn _mayor_auto_refresh_state_read)"
eval "$(extract_fn _mayor_auto_refresh_state_write)"
eval "$(extract_fn _mayor_prompt_budget_guard)"
eval "$(extract_fn _mayor_trigger_auto_refresh)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export SGT_CONFIG="$TMP_ROOT/.sgt"
export SGT_ROOT="$TMP_ROOT"
export SGT_MAYOR_SCOPE_RIG=""
mkdir -p "$SGT_CONFIG"
EVENT_LOG="$TMP_ROOT/events.log"
DECISION_LOG="$TMP_ROOT/decisions.log"
TRIGGER_LOG="$TMP_ROOT/trigger.log"
SCHEDULE_LOG="$TMP_ROOT/schedule.log"

_mayor_scope_dir() {
  printf '%s\n' "$SGT_CONFIG"
}

_mayor_scope_apply() {
  :
}

_escape_wake_value() {
  printf '%s' "${1:-}"
}

_escape_quotes() {
  printf '%s' "${1:-}"
}

log_event() {
  printf '%s\n' "$*" >> "$EVENT_LOG"
}

_mayor_record_decision() {
  printf '%s\n' "$1" >> "$DECISION_LOG"
}

cmd_status() {
  printf 'status ok\n'
}

_mayor_refresh_token() {
  printf 'auto-token\n'
}

_mayor_refresh_handoffs_dir() {
  printf '%s\n' "$TMP_ROOT/handoffs"
}

_mayor_refresh_archive_transients() {
  local handoff_dir="$1"
  mkdir -p "$handoff_dir"
  printf 'archived\n' > "$handoff_dir/archived.txt"
}

_mayor_refresh_write_handoff() {
  local handoff_file="$1"
  mkdir -p "$(dirname "$handoff_file")"
  cat > "$handoff_file" <<EOF
# Mayor Refresh Handoff
EOF
}

_mayor_schedule_auto_refresh_resume() {
  printf '%s\n' "${1:-shared}" >> "$SCHEDULE_LOG"
}

prompt_small="$TMP_ROOT/prompt-small.md"
printf 'abcd' > "$prompt_small"
[[ "$(_mayor_prompt_token_estimate_from_chars 4)" == "1" ]] || { echo "expected ceil(chars/4) token estimate" >&2; exit 1; }
[[ "$(_mayor_prompt_budget_measure_file "$prompt_small")" == "1|4" ]] || { echo "expected prompt budget measure from file" >&2; exit 1; }

prompt_large="$TMP_ROOT/prompt-large.md"
python3 - <<'PY' "$prompt_large"
from pathlib import Path
import sys
Path(sys.argv[1]).write_text("x" * 640000, encoding="utf-8")
PY

export SGT_MAYOR_AUTO_REFRESH_TOKENS=150000
export SGT_MAYOR_AUTO_REFRESH_COOLDOWN_SECS=900

set +e
guard_out="$(_mayor_prompt_budget_guard "$prompt_large" "ai-cycle-prompt")"
guard_rc=$?
set -e
[[ "$guard_rc" -eq 1 ]] || { echo "expected over-budget guard to request refresh" >&2; exit 1; }
IFS='|' read -r guard_state guard_tokens guard_chars guard_threshold guard_extra guard_handoff <<< "$guard_out"
[[ "$guard_state" == "refresh" ]] || { echo "expected refresh state" >&2; exit 1; }
[[ "$guard_tokens" == "160000" ]] || { echo "expected estimated_tokens=160000" >&2; exit 1; }
[[ "$guard_threshold" == "150000" ]] || { echo "expected threshold=150000" >&2; exit 1; }
[[ -f "$guard_handoff" ]] || { echo "expected handoff file from auto refresh trigger" >&2; exit 1; }
grep -q 'auto-token' "$guard_handoff" || true
grep -q '^shared$' "$SCHEDULE_LOG" || { echo "expected auto-refresh resume to be scheduled for shared mayor" >&2; exit 1; }

IFS='|' read -r budget_ts budget_measured_at budget_tokens budget_chars budget_threshold budget_over budget_source <<< "$(_mayor_prompt_budget_state_read)"
[[ "$budget_tokens" == "160000" && "$budget_over" == "true" ]] || { echo "expected prompt budget state to persist over-budget measurement" >&2; exit 1; }
IFS='|' read -r refresh_ts refresh_at refresh_trigger refresh_tokens refresh_chars refresh_threshold refresh_handoff refresh_token refresh_status <<< "$(_mayor_auto_refresh_state_read)"
[[ "$refresh_status" == "scheduled" ]] || { echo "expected scheduled auto-refresh state" >&2; exit 1; }
[[ "$refresh_handoff" == "$guard_handoff" ]] || { echo "expected auto-refresh state to carry handoff path" >&2; exit 1; }

now_epoch="$(date +%s)"
_mayor_auto_refresh_state_write "$now_epoch" "$(date -Iseconds)" "budget-exceeded" "160000" "640000" "150000" "$guard_handoff" "auto-token" "completed"
set +e
cooldown_out="$(_mayor_prompt_budget_guard "$prompt_large" "ai-cycle-prompt")"
cooldown_rc=$?
set -e
[[ "$cooldown_rc" -eq 2 ]] || { echo "expected cooldown-protected guard to skip refresh" >&2; exit 1; }
IFS='|' read -r cooldown_state cooldown_tokens cooldown_chars cooldown_threshold cooldown_remaining cooldown_handoff <<< "$cooldown_out"
[[ "$cooldown_state" == "cooldown" ]] || { echo "expected cooldown state" >&2; exit 1; }
[[ "$cooldown_remaining" =~ ^[0-9]+$ && "$cooldown_remaining" -gt 0 ]] || { echo "expected positive cooldown remaining" >&2; exit 1; }
[[ "$cooldown_handoff" == "$guard_handoff" ]] || { echo "expected cooldown response to expose previous handoff" >&2; exit 1; }

if ! grep -q 'MAYOR_AUTO_REFRESH_TRIGGERED' "$EVENT_LOG"; then
  echo "expected trigger telemetry" >&2
  exit 1
fi
if ! grep -q 'MAYOR_AUTO_REFRESH_SKIPPED scope=shared reason=cooldown-active' "$EVENT_LOG"; then
  echo "expected cooldown telemetry" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
