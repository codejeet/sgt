#!/usr/bin/env bash
# test_witness_stalled_followup_guard.sh — Stalled worker cleanup must leave durable replacement follow-up when re-dispatch fails.

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

eval "$(extract_fn _witness_record_stalled_followup)"
eval "$(extract_fn _witness_pr_meta)"
eval "$(extract_fn _witness_loop)"

export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_POLECATS="$SGT_CONFIG/polecats"
export SGT_ACCEPTANCE_BLOCKERS="$SGT_CONFIG/acceptance-blockers"
export SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_POLECATS" "$SGT_ACCEPTANCE_BLOCKERS" "$SGT_ROOT/rigs/rig-one" "$TMP_ROOT/worktrees"

TMUX_ACTIVE_FILE="$TMP_ROOT/tmux-active"
GH_COMMENT_FILE="$TMP_ROOT/gh-comments"
WAKE_FILE="$TMP_ROOT/wake-events"
BLOCKER_FILE="$TMP_ROOT/blockers"
CONTEXT_FILE="$TMP_ROOT/context.log"

printf 'https://github.com/acme/demo\n' > "$SGT_ROOT/.sgt-rig-one-repo"
echo "0" > "$TMUX_ACTIVE_FILE"
: > "$GH_COMMENT_FILE"
: > "$WAKE_FILE"
: > "$BLOCKER_FILE"
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
_ensure_context_file() {
  echo "$CONTEXT_FILE"
}
_context_append_acceptance_blocker() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$CONTEXT_FILE"
}
_acceptance_blocker_write() {
  local rig="$1" evidence="$2" requester="$3" source="$4"
  printf '%s\n' "$evidence" > "$TMP_ROOT/evidence.md"
  printf 'blocker-123\n' > /dev/null
  printf '%s|%s|%s|%s\n' "$rig" "$requester" "$source" "blocker-123" >> "$BLOCKER_FILE"
  printf 'blocker-123\n'
}
_wake_mayor() {
  printf '%s\n' "$1" >> "$WAKE_FILE"
}

_write_agent_heartbeat() { :; }
_wake_refinery() { :; }
_pr_head_sha() { echo "deadbeef"; }
_merge_queue_enqueue_polecat() { return 1; }
_ai_backend_default() { echo "codex"; }
_resling_existing_issue() { return 1; }

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
  if [[ "$args" == *" issue view "* ]]; then
    printf 'Stalled issue title\n'
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

echo "=== witness stalled worker follow-up guard ==="
make_polecat "rig-one-stalled" "sgt/rig-one-stalled"
echo "0" > "$TMUX_ACTIVE_FILE"
run_witness_once

if [[ -f "$SGT_POLECATS/rig-one-stalled" ]]; then
  echo "expected stalled polecat state file to be removed after cleanup" >&2
  exit 1
fi
if ! grep -q 'WITNESS_STALLED rig-one-stalled issue=#177' "$SGT_LOG"; then
  echo "expected stalled worker detection log" >&2
  cat "$SGT_LOG" >&2
  exit 1
fi
if ! grep -q 'WITNESS_STALLED_FOLLOWUP_REQUIRED polecat=rig-one-stalled rig=rig-one issue=#177 blocker_id=blocker-123 reason_code=witness-stalled-resling-failed' "$SGT_LOG"; then
  echo "expected durable follow-up log when re-sling fails" >&2
  cat "$SGT_LOG" >&2
  exit 1
fi
if ! grep -q 'acceptance-blocker:rig-one:blocker-123' "$WAKE_FILE"; then
  echo "expected mayor wake for stalled-worker acceptance blocker" >&2
  cat "$WAKE_FILE" >&2
  exit 1
fi
if ! grep -q 'blocker-123' "$BLOCKER_FILE"; then
  echo "expected acceptance blocker creation for stalled worker" >&2
  cat "$BLOCKER_FILE" >&2
  exit 1
fi
if ! grep -q 'Do not close this incident without replacement work item/PR' "$GH_COMMENT_FILE"; then
  echo "expected issue comment to block silent closure without replacement work" >&2
  cat "$GH_COMMENT_FILE" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
