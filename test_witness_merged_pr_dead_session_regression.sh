#!/usr/bin/env bash
# test_witness_merged_pr_dead_session_regression.sh — witness should treat merged PRs as complete even after session death.

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

eval "$(extract_fn _witness_pr_meta)"
eval "$(extract_fn _witness_loop)"

export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_POLECATS="$SGT_CONFIG/polecats"
export SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_POLECATS" "$SGT_ROOT/rigs/rig-one" "$TMP_ROOT/worktrees"

TMUX_ACTIVE_FILE="$TMP_ROOT/tmux-active"
TMUX_KILL_COUNT_FILE="$TMP_ROOT/tmux-kill-count"
GH_COMMENT_FILE="$TMP_ROOT/gh-comments"
GH_RESLING_FILE="$TMP_ROOT/resling-calls"
GH_CALLS_FILE="$TMP_ROOT/gh-pr-list-calls"

printf 'https://github.com/acme/demo\n' > "$SGT_ROOT/.sgt-rig-one-repo"
echo "0" > "$TMUX_ACTIVE_FILE"
echo "0" > "$TMUX_KILL_COUNT_FILE"
: > "$GH_COMMENT_FILE"
: > "$GH_RESLING_FILE"
: > "$GH_CALLS_FILE"

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

_write_agent_heartbeat() { :; }
_wake_refinery() { :; }
_pr_head_sha() { echo "deadbeef"; }
_merge_queue_enqueue_polecat() { return 1; }
_ai_backend_default() { echo "codex"; }
_resling_existing_issue() {
  printf '%s\n' "$*" >> "$GH_RESLING_FILE"
}

tmux() {
  if [[ "${1:-}" == "has-session" ]]; then
    [[ "$(cat "$TMUX_ACTIVE_FILE")" == "1" ]]
    return
  fi
  if [[ "${1:-}" == "capture-pane" ]]; then
    printf '%s\n' "${TMUX_CAPTURE_PANE_OUTPUT:-}"
    return 0
  fi
  if [[ "${1:-}" == "kill-session" ]]; then
    local next
    next=$(( $(cat "$TMUX_KILL_COUNT_FILE") + 1 ))
    echo "$next" > "$TMUX_KILL_COUNT_FILE"
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
    printf '%s\n' "$args" >> "$GH_CALLS_FILE"
    if [[ "$args" != *" --state all "* ]]; then
      echo ""
      return 0
    fi
    if [[ "$args" == *" --json number,state "* ]]; then
      printf '178\tMERGED\n'
      return 0
    fi
    if [[ "$args" == *" --json number "* ]]; then
      printf '178\n'
      return 0
    fi
    echo ""
    return 0
  fi
  if [[ "$args" == *" issue comment "* ]]; then
    printf '%s\n' "$args" >> "$GH_COMMENT_FILE"
    return 0
  fi
  if [[ "$args" == *" issue view "* ]]; then
    printf 'Issue title\n'
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
  cat > "$SGT_POLECATS/$name" <<STATE
SESSION=sgt-$name
BRANCH=$branch
ISSUE=177
WORKTREE=$worktree
CREATED=2026-03-10T00:00:00Z
REPO=https://github.com/acme/demo
STATE
}

assert_no_stalled_side_effects() {
  local name="$1"
  if grep -q 'WITNESS_STALLED' "$SGT_LOG"; then
    echo "expected merged PR path to avoid WITNESS_STALLED" >&2
    cat "$SGT_LOG" >&2
    exit 1
  fi
  if [[ -s "$GH_COMMENT_FILE" ]]; then
    echo "expected merged PR path to avoid issue comments" >&2
    cat "$GH_COMMENT_FILE" >&2
    exit 1
  fi
  if [[ -s "$GH_RESLING_FILE" ]]; then
    echo "expected merged PR path to avoid re-sling" >&2
    cat "$GH_RESLING_FILE" >&2
    exit 1
  fi
  if [[ -f "$SGT_POLECATS/$name" ]]; then
    echo "expected merged PR path to remove polecat state file" >&2
    exit 1
  fi
  if ! grep -q "WITNESS_MERGED $name" "$SGT_LOG"; then
    echo "expected merged PR path to log WITNESS_MERGED for $name" >&2
    cat "$SGT_LOG" >&2
    exit 1
  fi
}

echo "=== witness merged PR dead-session regression ==="
make_polecat "rig-one-dead" "sgt/rig-one-dead"
echo "0" > "$TMUX_ACTIVE_FILE"
TMUX_CAPTURE_PANE_OUTPUT=""
run_witness_once
assert_no_stalled_side_effects "rig-one-dead"
if ! grep -q -- '--state all' "$GH_CALLS_FILE"; then
  echo "expected dead-session PR lookup to include --state all" >&2
  cat "$GH_CALLS_FILE" >&2
  exit 1
fi

echo "=== witness merged PR idle-prompt regression ==="
: > "$SGT_LOG"
: > "$GH_COMMENT_FILE"
: > "$GH_RESLING_FILE"
: > "$GH_CALLS_FILE"
echo "0" > "$TMUX_KILL_COUNT_FILE"
make_polecat "rig-one-idle" "sgt/rig-one-idle"
echo "1" > "$TMUX_ACTIVE_FILE"
TMUX_CAPTURE_PANE_OUTPUT=$'\u276f'
run_witness_once
assert_no_stalled_side_effects "rig-one-idle"
if [[ "$(cat "$TMUX_KILL_COUNT_FILE")" != "1" ]]; then
  echo "expected idle merged PR path to kill stale tmux session exactly once" >&2
  exit 1
fi
if ! grep -q 'WITNESS_IDLE_DETECTED rig-one-idle' "$SGT_LOG"; then
  echo "expected idle merged PR path to log WITNESS_IDLE_DETECTED" >&2
  cat "$SGT_LOG" >&2
  exit 1
fi
if ! grep -q -- '--state all' "$GH_CALLS_FILE"; then
  echo "expected idle PR lookup to include --state all" >&2
  cat "$GH_CALLS_FILE" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
