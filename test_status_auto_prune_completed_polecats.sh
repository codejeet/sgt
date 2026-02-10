#!/usr/bin/env bash
# test_status_auto_prune_completed_polecats.sh — status auto-prunes dead completed polecats by PR state.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

TMUX_ACTIVE_FILE="$TMP_ROOT/tmux-active"
echo "0" > "$TMUX_ACTIVE_FILE"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

active_file="${SGT_TEST_TMUX_ACTIVE_FILE:?missing SGT_TEST_TMUX_ACTIVE_FILE}"
if [[ "${1:-}" == "has-session" ]]; then
  if [[ -f "$active_file" ]] && [[ "$(cat "$active_file")" == "1" ]]; then
    exit 0
  fi
  exit 1
fi
if [[ "${1:-}" == "kill-session" ]]; then
  echo "0" > "$active_file"
  exit 0
fi
echo "mock tmux unsupported: $*" >&2
exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

args=" $* "
pr_state="${SGT_TEST_PR_STATE:-OPEN}"
pr_number="${SGT_TEST_PR_NUMBER:-77}"
issue_state="${SGT_TEST_ISSUE_STATE:-OPEN}"

if [[ "$args" == *" issue view "* ]]; then
  printf '%s\n' "$issue_state"
  exit 0
fi

if [[ "$args" == *" pr list "* ]]; then
  if [[ "$args" == *" --json number,state,title "* ]]; then
    if [[ "$pr_state" == "NONE" ]]; then
      echo ""
    else
      printf '%s\t%s\t%s\n' "$pr_number" "$pr_state" "Mock PR $pr_state"
    fi
    exit 0
  fi
  if [[ "$args" == *" --json number,state "* ]]; then
    if [[ "$pr_state" == "NONE" ]]; then
      echo "0|"
    else
      printf '%s|%s\n' "$pr_number" "$pr_state"
    fi
    exit 0
  fi
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

ENV_PREFIX=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM="${TERM:-xterm}"
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_TEST_TMUX_ACTIVE_FILE="$TMUX_ACTIVE_FILE"
)

make_polecat() {
  local name="$1"
  local worktree="$HOME_DIR/sgt/polecats/$name"
  mkdir -p "$worktree"
  cat > "$HOME_DIR/sgt/.sgt/polecats/$name" <<STATE
RIG=test
REPO=https://github.com/acme/demo
ISSUE=70
BRANCH=sgt/$name
WORKTREE=$worktree
SESSION=sgt-$name
DEFAULT_BRANCH=master
STATE
}

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"
'

# Case 1: OPEN PR stays tracked.
make_polecat "test-open"
"${ENV_PREFIX[@]}" SGT_TEST_PR_STATE="OPEN" SGT_TEST_PR_NUMBER="77" bash --noprofile --norc -c '
set -euo pipefail
sgt status > "$SGT_ROOT/status-open.out" 2> "$SGT_ROOT/status-open.err"
if [[ -s "$SGT_ROOT/status-open.err" ]]; then
  echo "expected no stderr for OPEN case" >&2
  cat "$SGT_ROOT/status-open.err" >&2
  exit 1
fi
if ! grep -q "test-open" "$SGT_ROOT/status-open.out"; then
  echo "expected OPEN polecat to remain listed in status output" >&2
  cat "$SGT_ROOT/status-open.out" >&2
  exit 1
fi
if [[ ! -f "$SGT_ROOT/.sgt/polecats/test-open" ]]; then
  echo "expected OPEN polecat state file to remain" >&2
  exit 1
fi
'

# Case 2: active MERGED polecat is not pruned.
echo "1" > "$TMUX_ACTIVE_FILE"
"${ENV_PREFIX[@]}" SGT_TEST_PR_STATE="MERGED" SGT_TEST_PR_NUMBER="88" bash --noprofile --norc -c '
set -euo pipefail
sgt status > "$SGT_ROOT/status-merged-active.out" 2> "$SGT_ROOT/status-merged-active.err"
if [[ -s "$SGT_ROOT/status-merged-active.err" ]]; then
  echo "expected no stderr for active MERGED case" >&2
  cat "$SGT_ROOT/status-merged-active.err" >&2
  exit 1
fi
if [[ ! -f "$SGT_ROOT/.sgt/polecats/test-open" ]]; then
  echo "expected active MERGED polecat state to remain" >&2
  exit 1
fi
'

# Case 3: dead MERGED polecat is auto-pruned.
echo "0" > "$TMUX_ACTIVE_FILE"
"${ENV_PREFIX[@]}" SGT_TEST_PR_STATE="MERGED" SGT_TEST_PR_NUMBER="88" bash --noprofile --norc -c '
set -euo pipefail
sgt status > "$SGT_ROOT/status-merged-dead.out" 2> "$SGT_ROOT/status-merged-dead.err"
if [[ -s "$SGT_ROOT/status-merged-dead.err" ]]; then
  echo "expected no stderr for dead MERGED case" >&2
  cat "$SGT_ROOT/status-merged-dead.err" >&2
  exit 1
fi
if grep -q "test-open" "$SGT_ROOT/status-merged-dead.out"; then
  echo "expected dead MERGED polecat to be removed from status output" >&2
  cat "$SGT_ROOT/status-merged-dead.out" >&2
  exit 1
fi
if [[ -f "$SGT_ROOT/.sgt/polecats/test-open" ]]; then
  echo "expected dead MERGED polecat state file to be removed" >&2
  exit 1
fi
if ! grep -q "POLECAT_AUTO_PRUNE source=status polecat=test-open pr=#88" "$SGT_ROOT/sgt.log"; then
  echo "expected concise status auto-prune log entry with polecat and PR number for MERGED" >&2
  cat "$SGT_ROOT/sgt.log" >&2
  exit 1
fi
'

# Case 4: dead CLOSED polecat is auto-pruned.
make_polecat "test-closed"
"${ENV_PREFIX[@]}" SGT_TEST_PR_STATE="CLOSED" SGT_TEST_PR_NUMBER="99" bash --noprofile --norc -c '
set -euo pipefail
sgt status > "$SGT_ROOT/status-closed-dead.out" 2> "$SGT_ROOT/status-closed-dead.err"
if [[ -s "$SGT_ROOT/status-closed-dead.err" ]]; then
  echo "expected no stderr for dead CLOSED case" >&2
  cat "$SGT_ROOT/status-closed-dead.err" >&2
  exit 1
fi
if grep -q "test-closed" "$SGT_ROOT/status-closed-dead.out"; then
  echo "expected dead CLOSED polecat to be removed from status output" >&2
  cat "$SGT_ROOT/status-closed-dead.out" >&2
  exit 1
fi
if [[ -f "$SGT_ROOT/.sgt/polecats/test-closed" ]]; then
  echo "expected dead CLOSED polecat state file to be removed" >&2
  exit 1
fi
if ! grep -q "POLECAT_AUTO_PRUNE source=status polecat=test-closed pr=#99" "$SGT_ROOT/sgt.log"; then
  echo "expected concise status auto-prune log entry with polecat and PR number for CLOSED" >&2
  cat "$SGT_ROOT/sgt.log" >&2
  exit 1
fi
'

# Case 5: idempotent after cleanup (no failures, nothing resurrected).
"${ENV_PREFIX[@]}" SGT_TEST_PR_STATE="CLOSED" SGT_TEST_PR_NUMBER="99" bash --noprofile --norc -c '
set -euo pipefail
sgt status > "$SGT_ROOT/status-idempotent.out" 2> "$SGT_ROOT/status-idempotent.err"
if [[ -s "$SGT_ROOT/status-idempotent.err" ]]; then
  echo "expected no stderr for idempotent replay case" >&2
  cat "$SGT_ROOT/status-idempotent.err" >&2
  exit 1
fi
if ! grep -q "none" "$SGT_ROOT/status-idempotent.out"; then
  echo "expected no tracked polecats after replay" >&2
  cat "$SGT_ROOT/status-idempotent.out" >&2
  exit 1
fi
'

echo "ALL TESTS PASSED"
