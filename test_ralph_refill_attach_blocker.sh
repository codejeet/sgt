#!/usr/bin/env bash
# test_ralph_refill_attach_blocker.sh — stranded Ralph refill failures should emit an explicit blocker with spawn/worktree root cause.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn log_event)"
eval "$(extract_fn _record_refill_attach_blocker)"
eval "$(extract_fn _mayor_recover_stranded_actionable_rig)"

export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_LOG="$TMP_ROOT/sgt.log"
mkdir -p "$SGT_CONFIG"
: > "$SGT_LOG"

BLOCKER_FILE="$TMP_ROOT/blockers"
WAKE_FILE="$TMP_ROOT/wakes"
COMMENT_FILE="$TMP_ROOT/comments"
: > "$BLOCKER_FILE"
: > "$WAKE_FILE"
: > "$COMMENT_FILE"

_repo_owner_repo() { printf '%s\n' "${1#https://github.com/}"; }
_repo_issue_url() { printf '%s/issues/%s\n' "$1" "$2"; }
_context_append_acceptance_blocker() { :; }
_context_python_bin() { return 1; }
_context_index_build() { :; }
_wake_mayor() { printf '%s\n' "$1" >> "$WAKE_FILE"; }
_workflow_backend_default() { printf '%s\n' 'github'; }
_forge_issue_comment_add() {
  local _backend="$1" repo="$2" issue="$3" body="$4"
  gh issue comment "$issue" --repo "$repo" --body "$body"
}
_acceptance_blocker_write() {
  printf '%s|%s|%s|%s\n' "$1" "$3" "$4" "blocker-ralph" >> "$BLOCKER_FILE"
  printf 'blocker-ralph\n'
}
_mayor_rig_hibernated() { return 1; }
_mayor_rig_activity_snapshot() { printf '%s\n' 'active|ralph state=underfilled target=3 active_lanes=0 admissible_lanes=1 underfilled=1 condition="Keep three live lanes"|1|0|0|0|0|ralph-underfilled|pending'; }
_plan_task_issue_matches_current_plan() { return 0; }
_issue_backend_dispatch_limited_reason() { return 1; }
_resling_find_existing_issue_polecat() { return 1; }
_sweep_watchdog_find_open_pr_for_issue() { return 1; }
_ai_backend_default() { printf '%s\n' 'codex'; }
_plan_pending_underfill_target() { printf '%s\n' '0'; }
_ralph_mode_snapshot_fields() { printf '%s\n' '1|Keep three live lanes|unmet|3|0|underfilled|condition unmet; active_lanes=0 target=3|0|1|1|0|0|1|1||||'; }

gh() {
  local args=" $* "
  if [[ "$args" == *" issue list "* ]]; then
    printf '91\tAttach refill lane\n'
    return 0
  fi
  if [[ "$args" == *" issue comment "* ]]; then
    printf '%s\n' "$args" >> "$COMMENT_FILE"
    return 0
  fi
  echo "unexpected gh call: $*" >&2
  return 1
}

_RESLING_LAST_FAILURE_REASON_CODE=""
_RESLING_LAST_FAILURE_DETAIL=""
_resling_existing_issue() {
  _RESLING_LAST_FAILURE_REASON_CODE="worktree-attach-failed"
  _RESLING_LAST_FAILURE_DETAIL="git worktree add failed: path already exists"
  echo "[resling] dispatch failed (mayor-zero-worker-recovery) for issue #91 — git worktree add failed: path already exists"
  return 1
}

_mayor_recover_stranded_actionable_rig demo https://github.com/acme/demo

grep -q 'MAYOR_STRANDED_RIG_RECOVERY_BLOCKED issue=#91 rig=demo repo=acme/demo reason_code=worktree-attach-failed' "$SGT_LOG"
grep -q 'REFILL_ATTACH_BLOCKER rig=demo issue=#91 blocker_id=blocker-ralph source_event=mayor-zero-worker-recovery reason_code=worktree-attach-failed' "$SGT_LOG"
grep -q 'demo|witness|worktree-attach-failed|blocker-ralph' "$BLOCKER_FILE"
grep -q 'acceptance-blocker:demo:blocker-ralph' "$WAKE_FILE"
grep -q 'worktree-attach-failed' "$COMMENT_FILE"

echo "ALL TESTS PASSED"
