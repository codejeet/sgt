#!/usr/bin/env bash
# test_ralph_live_polecat_lane_accounting.sh — Ralph active lanes must require a live polecat on the issue.

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

eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _polecat_start_grace_secs)"
eval "$(extract_fn _polecat_counts_as_active)"
eval "$(extract_fn _active_polecat_issue_numbers)"
eval "$(extract_fn _plan_state_path)"
eval "$(extract_fn _plan_file_path)"
eval "$(sed -n '/^_plan_ralph_snapshot()/,/^_president_last_action_snapshot()/p' "$SGT_SCRIPT" | sed '$d')"

export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_POLECATS="$SGT_CONFIG/polecats"
export SGT_PLAN_STATE_DIR="$SGT_CONFIG/plan-state"
export SGT_LOG="$TMP_ROOT/sgt.log"
mkdir -p "$SGT_POLECATS" "$SGT_PLAN_STATE_DIR" "$SGT_ROOT/rigs/pmkb" "$TMP_ROOT/worktrees/stale" "$TMP_ROOT/worktrees/live"
: > "$SGT_LOG"

log_event() {
  printf '%s\n' "${1:-}" >> "$SGT_LOG"
}

rig_path() {
  printf '%s/rigs/%s\n' "$SGT_ROOT" "$1"
}

TMUX_LIVE=1
tmux() {
  if [[ "${1:-}" == "has-session" && "${3:-}" == "sgt-pmkb-live" && "$TMUX_LIVE" == "1" ]]; then
    return 0
  fi
  return 1
}

cat > "$SGT_POLECATS/pmkb-stale" <<STATE
RIG=pmkb
REPO=https://github.com/acme/pmkb
ISSUE=1300
BRANCH=sgt/pmkb-stale
WORKTREE=$TMP_ROOT/worktrees/stale
SESSION=sgt-pmkb-stale
CREATED=2026-04-02T00:00:00Z
STATUS=running
STATE

cat > "$SGT_POLECATS/pmkb-live" <<STATE
RIG=pmkb
REPO=https://github.com/acme/pmkb
ISSUE=1301
BRANCH=sgt/pmkb-live
WORKTREE=$TMP_ROOT/worktrees/live
SESSION=sgt-pmkb-live
CREATED=2026-04-02T00:00:00Z
STATUS=running
STATE

cat > "$SGT_ROOT/rigs/pmkb/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "pmkb",
  "ralph": {
    "enabled": true,
    "condition": "Keep PMKB lanes live",
    "target_concurrency": 2
  },
  "acceptance": { "status": "pending" },
  "tasks": [
    { "id": "PK1300", "title": "Stale lane" },
    { "id": "PK1301", "title": "Live lane" }
  ]
}
JSON

cat > "$SGT_PLAN_STATE_DIR/pmkb.json" <<'JSON'
{
  "tasks": {
    "PK1300": { "status": "in_progress", "issue_number": "1300" },
    "PK1301": { "status": "in_progress", "issue_number": "1301" }
  }
}
JSON

snapshot="$(_plan_ralph_snapshot pmkb)"
IFS='|' read -r enabled unmet condition target active underfilled policy <<< "$snapshot"
[[ "$enabled" == "1" ]]
[[ "$unmet" == "1" ]]
[[ "$target" == "2" ]]
[[ "$active" == "1" ]] || {
  echo "expected only the live polecat issue to count active, got snapshot=$snapshot" >&2
  exit 1
}
[[ "$underfilled" == "1" ]]

TMUX_LIVE=0
rm -rf "$TMP_ROOT/worktrees/live"
snapshot="$(_plan_ralph_snapshot pmkb)"
IFS='|' read -r _enabled _unmet _condition _target active underfilled _policy <<< "$snapshot"
[[ "$active" == "0" ]] || {
  echo "expected missing live worktree to remove remaining active lane, got snapshot=$snapshot" >&2
  exit 1
}
[[ "$underfilled" == "1" ]]

echo "ALL TESTS PASSED"
