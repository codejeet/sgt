#!/usr/bin/env bash
# test_mayor_live_polecat_count_regression.sh — dead stale polecat files must not count as live in mayor revalidation.

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
eval "$(extract_fn _polecat_start_grace_secs)"
eval "$(extract_fn _polecat_counts_as_active)"
eval "$(extract_fn _active_polecat_count)"

export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_POLECATS="$SGT_CONFIG/polecats"
export SGT_LOG="$TMP_ROOT/sgt.log"
mkdir -p "$SGT_POLECATS" "$SGT_ROOT/polecats"

log_event() {
  local line="${1:-}"
  printf '%s\n' "$line" >> "$SGT_LOG"
}

tmux() {
  if [[ "${1:-}" == "has-session" ]]; then
    return 1
  fi
  echo "mock tmux unsupported: $*" >&2
  return 1
}

stale_worktree="$SGT_ROOT/polecats/sgt-stale"
mkdir -p "$stale_worktree"
cat > "$SGT_POLECATS/sgt-stale" <<EOF
RIG=sgt
REPO=https://github.com/codejeet/sgt
ISSUE=251
BRANCH=sgt/sgt-stale
SESSION=sgt-sgt-stale
WORKTREE=$stale_worktree
CREATED=2026-03-26T20:00:00+01:00
STATUS=running
EOF

starting_worktree="$SGT_ROOT/polecats/sgt-starting"
mkdir -p "$starting_worktree"
cat > "$SGT_POLECATS/sgt-starting" <<EOF
RIG=sgt
REPO=https://github.com/codejeet/sgt
ISSUE=252
BRANCH=sgt/sgt-starting
SESSION=sgt-sgt-starting
WORKTREE=$starting_worktree
CREATED=$(date -Iseconds)
STATUS=running
EOF

if [[ "$(_active_polecat_count sgt)" != "1" ]]; then
  echo "expected only the fresh starting polecat to count as active" >&2
  exit 1
fi

rm -rf "$starting_worktree"
if [[ "$(_active_polecat_count sgt)" != "0" ]]; then
  echo "expected dead stale polecat files to stop counting as active once startup grace expires or worktree disappears" >&2
  exit 1
fi

if [[ -f "$SGT_POLECATS/sgt-starting" ]]; then
  echo "expected missing-worktree dead polecat state to be auto-pruned" >&2
  exit 1
fi

if ! grep -q 'POLECAT_COUNT_AUTO_PRUNE polecat=sgt-starting reason_code=dead-session-missing-worktree' "$SGT_LOG"; then
  echo "expected structured auto-prune telemetry for missing-worktree stale polecat state" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
