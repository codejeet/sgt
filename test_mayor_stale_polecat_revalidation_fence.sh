#!/usr/bin/env bash
# test_mayor_stale_polecat_revalidation_fence.sh — Regression checks for mayor stale-polecat merge/close reconciliation cleanup fence.

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

eval "$(extract_fn _repo_owner_repo)"
eval "$(extract_fn _repo_owner_repo_strict)"
eval "$(extract_fn _repo_owner_repo_url)"
eval "$(extract_fn _rig_repo_resolve_error)"
eval "$(extract_fn _rig_repo_resolve_error_unpack)"
eval "$(extract_fn _resolve_rig_repo_canonical)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _one_line)"
eval "$(extract_fn _mayor_dispatch_trigger_key_id)"
eval "$(extract_fn _mayor_stale_polecat_fence_dir)"
eval "$(extract_fn _mayor_stale_polecat_fence_key)"
eval "$(extract_fn _mayor_stale_polecat_pr_snapshot)"
eval "$(extract_fn _mayor_cleanup_stale_polecat)"
eval "$(extract_fn _mayor_reconcile_stale_polecats)"

export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_POLECATS="$SGT_CONFIG/polecats"
export SGT_RIGS="$SGT_CONFIG/rigs"
export SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_POLECATS" "$SGT_RIGS" "$SGT_ROOT/rigs/rig-one" "$SGT_ROOT/worktree"
printf 'https://github.com/acme/demo\n' > "$SGT_RIGS/rig-one"

DECISION_LOG="$TMP_ROOT/mayor-decisions.log"
KILL_COUNT_FILE="$TMP_ROOT/kill-count"
TMUX_ACTIVE_FILE="$TMP_ROOT/tmux-active"
echo "0" > "$KILL_COUNT_FILE"
echo "1" > "$TMUX_ACTIVE_FILE"
GH_ISSUE_STATE="OPEN"
GH_PR_STATE="OPEN"
GH_PR_NUMBER="88"

log_event() {
  local line="${1:-}"
  printf '%s\n' "$line" >> "$SGT_LOG"
}

_mayor_record_decision() {
  local entry="${1:-}"
  local context="${2:-cycle}"
  printf '%s|%s\n' "$context" "$entry" >> "$DECISION_LOG"
}

rig_path() {
  local rig="${1:-}"
  echo "$SGT_ROOT/rigs/$rig"
}

rig_repo() {
  local rig="${1:-}"
  cat "$SGT_RIGS/$rig"
}

gh() {
  if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
    printf '%s\n' "$GH_ISSUE_STATE"
    return 0
  fi
  if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
    if [[ "$GH_PR_NUMBER" == "0" ]]; then
      printf '0|\n'
    else
      printf '%s|%s\n' "$GH_PR_NUMBER" "$GH_PR_STATE"
    fi
    return 0
  fi
  echo "mock gh unsupported: $*" >&2
  return 1
}

tmux() {
  if [[ "${1:-}" == "has-session" ]]; then
    if [[ "$(cat "$TMUX_ACTIVE_FILE")" == "1" ]]; then
      return 0
    fi
    return 1
  fi
  if [[ "${1:-}" == "kill-session" ]]; then
    local next
    next=$(( $(cat "$KILL_COUNT_FILE") + 1 ))
    echo "$next" > "$KILL_COUNT_FILE"
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
  echo "mock git unsupported: $*" >&2
  return 1
}

polecat_file="$SGT_POLECATS/rig-one-cat"
worktree="$SGT_ROOT/worktree/rig-one-cat"
mkdir -p "$worktree"
cat > "$polecat_file" <<PSTATE
RIG=rig-one
REPO=https://github.com/acme/demo
ISSUE=117
BRANCH=sgt/rig-one-cat
SESSION=sgt-rig-one-cat
WORKTREE=$worktree
STATUS=running
PSTATE

# Case 1: in-flight OPEN issue + OPEN PR => no cleanup.
mapfile -t case1_lines < <(_mayor_reconcile_stale_polecats)
if [[ "${#case1_lines[@]}" -ne 0 ]]; then
  echo "expected no stale-polecat cleanup for normal in-flight work" >&2
  exit 1
fi
if [[ ! -f "$polecat_file" ]]; then
  echo "expected in-flight polecat state to remain untouched" >&2
  exit 1
fi
if [[ "$(cat "$KILL_COUNT_FILE")" -ne 0 ]]; then
  echo "expected no session kills for normal in-flight work" >&2
  exit 1
fi
if [[ -f "$DECISION_LOG" ]]; then
  echo "expected no cleanup decision log entries for normal in-flight work" >&2
  exit 1
fi

# Case 2: active session + merged PR => no cleanup (active polecats must survive).
GH_PR_STATE="MERGED"
mapfile -t case2_lines < <(_mayor_reconcile_stale_polecats)
if [[ "${#case2_lines[@]}" -ne 0 ]]; then
  echo "expected no stale cleanup while polecat session is still active" >&2
  exit 1
fi
if [[ ! -f "$polecat_file" ]]; then
  echo "expected active merged polecat state to remain untouched" >&2
  exit 1
fi
if [[ "$(cat "$KILL_COUNT_FILE")" -ne 0 ]]; then
  echo "expected no session kills while polecat is active" >&2
  exit 1
fi

# Case 3: merged transition on dead session => stale cleanup + one structured decision entry.
echo "0" > "$TMUX_ACTIVE_FILE"
mapfile -t case3_lines < <(_mayor_reconcile_stale_polecats)
if [[ "${#case3_lines[@]}" -ne 1 ]]; then
  echo "expected exactly one merged-transition stale-polecat cleanup action" >&2
  exit 1
fi
if [[ "${case3_lines[0]}" != CLEANED\|rig-one-cat\|stale-pr-merged\|* ]]; then
  echo "unexpected merged cleanup payload: ${case3_lines[0]}" >&2
  exit 1
fi
if [[ -f "$polecat_file" ]]; then
  echo "expected merged-transition stale polecat state file to be removed" >&2
  exit 1
fi
if [[ -d "$worktree" ]]; then
  echo "expected merged-transition stale polecat worktree to be removed" >&2
  exit 1
fi
if [[ "$(cat "$KILL_COUNT_FILE")" -ne 0 ]]; then
  echo "expected no stale-polecat session kills after merged transition when session is already dead" >&2
  exit 1
fi
if [[ ! -f "$DECISION_LOG" ]]; then
  echo "expected stale cleanup decision log to be created" >&2
  exit 1
fi
if [[ "$(grep -c 'stale-polecat-cleanup|MAYOR POLECAT CLEANUP reason_code=stale-pr-merged polecat=rig-one-cat' "$DECISION_LOG" || true)" -ne 1 ]]; then
  echo "expected exactly one structured stale-pr-merged cleanup decision entry" >&2
  exit 1
fi
if [[ "$(grep -c 'MAYOR_POLECAT_CLEANUP reason_code=stale-pr-merged polecat=rig-one-cat' "$SGT_LOG" || true)" -ne 1 ]]; then
  echo "expected exactly one structured stale-pr-merged cleanup activity log entry" >&2
  exit 1
fi

# Case 4: restart replay with same stale polecat metadata => idempotent (no duplicate kill/logging).
mkdir -p "$worktree"
cat > "$polecat_file" <<PSTATE
RIG=rig-one
REPO=https://github.com/acme/demo
ISSUE=117
BRANCH=sgt/rig-one-cat
SESSION=sgt-rig-one-cat
WORKTREE=$worktree
STATUS=running
PSTATE
echo "0" > "$TMUX_ACTIVE_FILE"

mapfile -t case4_lines < <(_mayor_reconcile_stale_polecats)
if [[ "${#case4_lines[@]}" -ne 1 ]]; then
  echo "expected replay pass to still converge stale polecat state" >&2
  exit 1
fi
if [[ "${case4_lines[0]}" != 'CLEANED|rig-one-cat|stale-pr-merged|cleanup-already-applied|117|88' ]]; then
  echo "expected replay pass to report cleanup-already-applied fence state" >&2
  exit 1
fi
if [[ "$(cat "$KILL_COUNT_FILE")" -ne 0 ]]; then
  echo "expected restart replay to avoid duplicate stale-polecat session kills" >&2
  exit 1
fi
if [[ "$(grep -c 'stale-polecat-cleanup|MAYOR POLECAT CLEANUP reason_code=stale-pr-merged polecat=rig-one-cat' "$DECISION_LOG" || true)" -ne 1 ]]; then
  echo "expected restart replay to avoid duplicate stale-polecat decision entries" >&2
  exit 1
fi
if [[ "$(grep -c 'MAYOR_POLECAT_CLEANUP reason_code=stale-pr-merged polecat=rig-one-cat' "$SGT_LOG" || true)" -ne 1 ]]; then
  echo "expected restart replay to avoid duplicate stale-polecat cleanup activity log events" >&2
  exit 1
fi
if [[ -f "$polecat_file" ]]; then
  echo "expected replay pass to leave no stale polecat state file" >&2
  exit 1
fi

# Case 5: closed (unmerged) PR transition on dead session => stale cleanup.
closed_polecat_file="$SGT_POLECATS/rig-one-cat-closed"
closed_worktree="$SGT_ROOT/worktree/rig-one-cat-closed"
mkdir -p "$closed_worktree"
cat > "$closed_polecat_file" <<PSTATE
RIG=rig-one
REPO=https://github.com/acme/demo
ISSUE=117
BRANCH=sgt/rig-one-cat-closed
SESSION=sgt-rig-one-cat-closed
WORKTREE=$closed_worktree
STATUS=running
PSTATE
GH_PR_STATE="CLOSED"
GH_PR_NUMBER="91"
mapfile -t case5_lines < <(_mayor_reconcile_stale_polecats)
if [[ "${#case5_lines[@]}" -ne 1 ]]; then
  echo "expected exactly one closed-transition stale-polecat cleanup action" >&2
  exit 1
fi
if [[ "${case5_lines[0]}" != CLEANED\|rig-one-cat-closed\|stale-pr-closed\|* ]]; then
  echo "unexpected closed cleanup payload: ${case5_lines[0]}" >&2
  exit 1
fi
if [[ -f "$closed_polecat_file" ]]; then
  echo "expected closed-transition stale polecat state file to be removed" >&2
  exit 1
fi
if [[ -d "$closed_worktree" ]]; then
  echo "expected closed-transition stale polecat worktree to be removed" >&2
  exit 1
fi
if [[ "$(grep -c 'MAYOR_POLECAT_CLEANUP reason_code=stale-pr-closed polecat=rig-one-cat-closed.*pr=#91' "$SGT_LOG" || true)" -ne 1 ]]; then
  echo "expected one stale-pr-closed cleanup activity log entry with PR number" >&2
  exit 1
fi

# Case 6: restart replay after CLOSED cleanup remains idempotent.
mkdir -p "$closed_worktree"
cat > "$closed_polecat_file" <<PSTATE
RIG=rig-one
REPO=https://github.com/acme/demo
ISSUE=117
BRANCH=sgt/rig-one-cat-closed
SESSION=sgt-rig-one-cat-closed
WORKTREE=$closed_worktree
STATUS=running
PSTATE
mapfile -t case6_lines < <(_mayor_reconcile_stale_polecats)
if [[ "${#case6_lines[@]}" -ne 1 ]]; then
  echo "expected closed replay pass to converge stale polecat state" >&2
  exit 1
fi
if [[ "${case6_lines[0]}" != 'CLEANED|rig-one-cat-closed|stale-pr-closed|cleanup-already-applied|117|91' ]]; then
  echo "expected closed replay pass to report cleanup-already-applied fence state" >&2
  exit 1
fi
if [[ -f "$closed_polecat_file" ]]; then
  echo "expected closed replay pass to leave no stale polecat state file" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
