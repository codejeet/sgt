#!/usr/bin/env bash
# test_witness_alive_stall_classification.sh — Alive polecats should distinguish quiet compute from true stalls.

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

eval "$(extract_fn _merge_queue_set_field)"
eval "$(extract_fn _polecat_quiet_output_stale_secs)"
eval "$(extract_fn _polecat_stall_secs)"
eval "$(extract_fn _polecat_busy_child_min_age_secs)"
eval "$(extract_fn _polecat_busy_child_min_cpu_pct)"
eval "$(extract_fn _polecat_output_age_seconds)"
eval "$(extract_fn _polecat_created_age_seconds)"
eval "$(extract_fn _polecat_session_root_pid)"
eval "$(extract_fn _polecat_find_busy_child)"
eval "$(extract_fn _polecat_runtime_classify)"
eval "$(extract_fn _polecat_issue_title)"
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
export SGT_MAYOR_RIG_ACTIVITY_DIR="$SGT_CONFIG/mayor-rig-activity"
export SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_POLECATS" "$SGT_MAYOR_RIG_ACTIVITY_DIR" "$SGT_ROOT/rigs/rig-one" "$TMP_ROOT/worktrees"

TMUX_ACTIVE_FILE="$TMP_ROOT/tmux-active"
GH_COMMENT_FILE="$TMP_ROOT/gh-comments"
WAKE_FILE="$TMP_ROOT/wake-events"
RESLING_FILE="$TMP_ROOT/resling-events"
PS_OUTPUT_FILE="$TMP_ROOT/ps-output"

printf 'https://github.com/acme/demo\n' > "$SGT_ROOT/.sgt-rig-one-repo"
echo "1" > "$TMUX_ACTIVE_FILE"
: > "$GH_COMMENT_FILE"
: > "$WAKE_FILE"
: > "$RESLING_FILE"
: > "$SGT_LOG"

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

_escape_quotes() { printf '%s' "$1"; }
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
_forge_issue_comment_add() {
  local _backend="$1" repo="$2" issue="$3" body="$4"
  gh issue comment "$issue" --repo "$repo" --body "$body"
}
_write_agent_heartbeat() { :; }
_wake_refinery() { printf '%s\n' "$1|$2" >> "$WAKE_FILE"; }
_ai_backend_default() { echo "codex"; }
_mayor_rig_activity_enabled() { return 1; }

_resling_existing_issue() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$7" >> "$RESLING_FILE"
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
  if [[ "${1:-}" == "display-message" ]]; then
    printf '100\n'
    return 0
  fi
  if [[ "${1:-}" == "kill-session" ]]; then
    echo "0" > "$TMUX_ACTIVE_FILE"
    return 0
  fi
  echo "mock tmux unsupported: $*" >&2
  return 1
}

ps() {
  if [[ "${1:-}" == "-eo" ]]; then
    cat "$PS_OUTPUT_FILE"
    return 0
  fi
  command ps "$@"
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
  if [[ "$args" == *" issue view "* ]]; then
    printf 'Alive stalled issue title\n'
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

make_alive_polecat() {
  local name="$1"
  local worktree="$TMP_ROOT/worktrees/$name"
  mkdir -p "$worktree"
  touch -d '45 minutes ago' "$worktree/.sgt-agent-output.log"
  cat > "$SGT_POLECATS/$name" <<STATE
SESSION=sgt-$name
BRANCH=sgt/$name
ISSUE=177
WORKTREE=$worktree
CREATED=$(date -d '45 minutes ago' -Iseconds)
REPO=https://github.com/acme/demo
OUTPUT_LOG=$worktree/.sgt-agent-output.log
STATE
}

echo "=== witness alive quiet classification ==="

make_alive_polecat "rig-one-busy"
cat > "$PS_OUTPUT_FILE" <<'EOF'
100 1 2700 0.0 S bash bash -lc codex exec
200 100 900 98.5 R python3 python3 scripts/long-report.py
EOF
echo "1" > "$TMUX_ACTIVE_FILE"
run_witness_once

if [[ ! -f "$SGT_POLECATS/rig-one-busy" ]]; then
  echo "expected busy long-running polecat to remain tracked" >&2
  exit 1
fi
if [[ -s "$RESLING_FILE" ]]; then
  echo "expected no resling for busy long-running polecat" >&2
  cat "$RESLING_FILE" >&2
  exit 1
fi
if ! grep -q 'classification=busy-long-running' "$SGT_LOG"; then
  echo "expected busy-long-running classification log" >&2
  cat "$SGT_LOG" >&2
  exit 1
fi
if ! grep -q 'RUNTIME_CLASSIFICATION=busy-long-running' "$SGT_POLECATS/rig-one-busy"; then
  echo "expected busy classification persisted in polecat state" >&2
  cat "$SGT_POLECATS/rig-one-busy" >&2
  exit 1
fi

rm -f "$SGT_POLECATS/rig-one-busy"
: > "$RESLING_FILE"
: > "$GH_COMMENT_FILE"
: > "$SGT_LOG"

make_alive_polecat "rig-one-stalled"
cat > "$PS_OUTPUT_FILE" <<'EOF'
100 1 2700 0.0 S bash bash -lc codex exec
EOF
echo "1" > "$TMUX_ACTIVE_FILE"
run_witness_once

if [[ -f "$SGT_POLECATS/rig-one-stalled" ]]; then
  echo "expected truly stalled alive polecat to be cleaned up" >&2
  exit 1
fi
if ! grep -q 'rig-one|177|Alive stalled issue title|witness-stalled' "$RESLING_FILE"; then
  echo "expected resling for truly stalled alive polecat" >&2
  cat "$RESLING_FILE" >&2
  exit 1
fi
if ! grep -q 'WITNESS_STALLED rig-one-stalled issue=#177 reason_code=no-substantive-child output_age=' "$SGT_LOG"; then
  echo "expected stalled classification log for alive session" >&2
  cat "$SGT_LOG" >&2
  exit 1
fi
if ! grep -q 'classified as truly stalled while still alive' "$GH_COMMENT_FILE"; then
  echo "expected operator-visible stalled classification comment" >&2
  cat "$GH_COMMENT_FILE" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
