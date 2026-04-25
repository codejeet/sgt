#!/usr/bin/env bash
# test_witness_codex_usage_limit_block.sh — Witness must block Codex usage-limit failures instead of re-slinging them.

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

eval "$(extract_fn _witness_record_backend_limit_followup)"
eval "$(extract_fn _polecat_issue_title)"
eval "$(extract_fn _polecat_output_log_path)"
eval "$(extract_fn _witness_dead_polecat_backend_limit)"
eval "$(extract_fn _witness_pr_meta)"
eval "$(extract_fn _witness_loop)"
eval "$(extract_fn _mayor_rig_activity_enabled)"
eval "$(extract_fn _mayor_rig_activity_file)"
eval "$(extract_fn _mayor_rig_activity_state_read)"
eval "$(extract_fn _mayor_rig_hibernation_mode)"
eval "$(extract_fn _mayor_rig_manually_hibernated)"

export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_POLECATS="$SGT_CONFIG/polecats"
export SGT_ACCEPTANCE_BLOCKERS="$SGT_CONFIG/acceptance-blockers"
export SGT_MAYOR_RIG_ACTIVITY_DIR="$SGT_CONFIG/mayor-rig-activity"
export SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_POLECATS" "$SGT_ACCEPTANCE_BLOCKERS" "$SGT_MAYOR_RIG_ACTIVITY_DIR" "$SGT_ROOT/rigs/rig-one" "$TMP_ROOT/worktrees"

TMUX_ACTIVE_FILE="$TMP_ROOT/tmux-active"
GH_COMMENT_FILE="$TMP_ROOT/gh-comments"
GH_EDIT_FILE="$TMP_ROOT/gh-edits"
WAKE_FILE="$TMP_ROOT/wake-events"
BLOCKER_FILE="$TMP_ROOT/blockers"
RESLING_FILE="$TMP_ROOT/resling-calls"
LABEL_FILE="$TMP_ROOT/labels"
CONTEXT_FILE="$TMP_ROOT/context.log"

printf 'https://github.com/acme/demo\n' > "$SGT_ROOT/.sgt-rig-one-repo"
echo "0" > "$TMUX_ACTIVE_FILE"
: > "$GH_COMMENT_FILE"
: > "$GH_EDIT_FILE"
: > "$WAKE_FILE"
: > "$BLOCKER_FILE"
: > "$RESLING_FILE"
: > "$LABEL_FILE"
: > "$CONTEXT_FILE"

log_event() {
  printf '%s\n' "${1:-}" >> "$SGT_LOG"
}

rig_repo() {
  local rig="${1:-}"
  cat "$SGT_ROOT/.sgt-${rig}-repo"
}

rig_path() {
  local rig="${1:-}"
  echo "$SGT_ROOT/rigs/$rig"
}

_repo_owner_repo() {
  local repo="${1:-}"
  printf '%s\n' "${repo#https://github.com/}"
}

_repo_issue_url() {
  local repo="${1:-}" issue="${2:-}"
  printf '%s/issues/%s\n' "$repo" "$issue"
}

_escape_quotes() { printf '%s' "$1"; }
_context_python_bin() { return 1; }
_context_index_build() { :; }
_ensure_context_file() { echo "$CONTEXT_FILE"; }
_context_append_acceptance_blocker() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$CONTEXT_FILE"
}
_acceptance_blocker_write() {
  printf '%s|%s|%s|%s\n' "$1" "$3" "$4" "blocker-usage-limit" >> "$BLOCKER_FILE"
  printf 'blocker-usage-limit\n'
}
_wake_mayor() {
  printf '%s\n' "$1" >> "$WAKE_FILE"
}
_ensure_labels_exist() {
  printf '%s\n' "$*" >> "$LABEL_FILE"
}

_workflow_backend_default() { echo "github"; }
_forge_pr_find_by_head_tsv() { return 0; }
_forge_issue_field() {
  local _backend="$1" _repo="$2" issue="$3" field="$4"
  if [[ "$field" == "title" ]]; then
    gh issue view "$issue" --repo "$_repo" --json title --jq '.title // ""'
    return
  fi
  return 1
}
_forge_issue_add_labels() {
  local _backend="$1" _repo="$2" issue="$3" labels="$4"
  printf '%s|%s\n' "$issue" "$labels" >> "$GH_EDIT_FILE"
}
_forge_issue_comment_add() {
  local _backend="$1" repo="$2" issue="$3" body="$4"
  gh issue comment "$issue" --repo "$repo" --body "$body"
}
_write_agent_heartbeat() { :; }
_wake_refinery() { :; }
_pr_head_sha() { echo "deadbeef"; }
_merge_queue_enqueue_polecat() { return 1; }
_ai_backend_default() { echo "codex"; }
_resling_existing_issue() {
  printf '%s\n' "$*" >> "$RESLING_FILE"
  return 0
}

tmux() {
  if [[ "${1:-}" == "has-session" ]]; then
    [[ "$(cat "$TMUX_ACTIVE_FILE")" == "1" ]]
    return
  fi
  if [[ "${1:-}" == "capture-pane" ]]; then
    printf '%s\n' ""
    return 0
  fi
  if [[ "${1:-}" == "kill-session" ]]; then
    echo "0" > "$TMUX_ACTIVE_FILE"
    return 0
  fi
  echo "mock tmux unsupported: $*" >&2
  return 1
}

git() {
  if [[ "${1:-}" == "-C" && "${3:-}" == "worktree" && "${4:-}" == "remove" ]]; then
    rm -rf "${6:-}" 2>/dev/null || true
    return 0
  fi
  if [[ "${1:-}" == "-C" && "${3:-}" == "push" && "${4:-}" == "origin" && "${5:-}" == "--delete" ]]; then
    return 0
  fi
  echo "mock git unsupported: $*" >&2
  return 1
}

gh() {
  local args=" $* "
  if [[ "$args" == *" pr list "* ]]; then
    echo ""
    return 0
  fi
  if [[ "$args" == *" issue comment "* ]]; then
    printf '%s\n' "$args" >> "$GH_COMMENT_FILE"
    return 0
  fi
  if [[ "$args" == *" issue edit "* ]]; then
    printf '%s\n' "$args" >> "$GH_EDIT_FILE"
    return 0
  fi
  if [[ "$args" == *" issue view "* ]]; then
    printf 'Blocked issue title\n'
    return 0
  fi
  echo "mock gh unsupported: $*" >&2
  return 1
}

run_witness_once() {
  (
    sleep() { exit 0; }
    _witness_loop "rig-one"
  )
}

make_polecat() {
  local name="$1"
  local branch="$2"
  local worktree="$TMP_ROOT/worktrees/$name"
  mkdir -p "$worktree"
  printf "You've hit your usage limit\n" > "$worktree/.sgt-agent-output.log"
  cat > "$SGT_POLECATS/$name" <<STATE
SESSION=sgt-$name
BRANCH=$branch
ISSUE=177
WORKTREE=$worktree
OUTPUT_LOG=$worktree/.sgt-agent-output.log
CREATED=2026-03-10T00:00:00Z
REPO=https://github.com/acme/demo
BACKEND=codex
STATE
}

make_polecat "rig-one-stalled" "sgt/rig-one-stalled"
echo "0" > "$TMUX_ACTIVE_FILE"
run_witness_once

if [[ -f "$SGT_POLECATS/rig-one-stalled" ]]; then
  echo "expected quota-limited polecat state file to be removed after cleanup" >&2
  exit 1
fi
if grep -q 'WITNESS_STALLED' "$SGT_LOG"; then
  echo "expected usage-limit path to avoid generic WITNESS_STALLED classification" >&2
  cat "$SGT_LOG" >&2
  exit 1
fi
grep -q 'WITNESS_BACKEND_LIMIT rig-one-stalled issue=#177 backend=codex reason_code=codex_usage_limit' "$SGT_LOG"
grep -q 'WITNESS_BACKEND_LIMIT_BLOCKED polecat=rig-one-stalled rig=rig-one issue=#177 blocker_id=blocker-usage-limit backend=codex reason_code=codex_usage_limit' "$SGT_LOG"
if [[ -s "$RESLING_FILE" ]]; then
  echo "expected usage-limit path not to attempt automatic re-sling" >&2
  cat "$RESLING_FILE" >&2
  exit 1
fi
grep -q 'acceptance-blocker:rig-one:blocker-usage-limit' "$WAKE_FILE"
grep -q 'backend-limited' "$GH_EDIT_FILE"
grep -q 'codex-usage-limit' "$GH_EDIT_FILE"
grep -q "You've hit your usage limit" "$GH_COMMENT_FILE"
grep -q 'Do not auto-resling until quota resets or backend policy changes' "$GH_COMMENT_FILE"

echo "ALL TESTS PASSED"
