#!/usr/bin/env bash
# test_sweep_stability.sh — Regression checks for deterministic sweep exits and errors.

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

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi

echo "mock tmux unsupported: $*" >&2
exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

mode="${SGT_TEST_GH_MODE:-open}"
args=" $* "

if [[ "$args" == *" pr list "* ]]; then
  case "$mode" in
    open)
      echo "OPEN"
      ;;
    lookup_race)
      echo ""
      ;;
    *)
      echo "unknown gh mode: $mode" >&2
      exit 1
      ;;
  esac
  exit 0
fi

if [[ "$args" == *" issue view "* && "$args" == *" --json state "* ]]; then
  case "$mode" in
    lookup_race)
      echo "CLOSED"
      ;;
    *)
      echo "OPEN"
      ;;
  esac
  exit 0
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
  SGT_TEST_GH_MODE="open"
)

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

worktree="$SGT_ROOT/polecats/test-aaaa1111"
mkdir -p "$worktree"
cat > "$SGT_ROOT/.sgt/polecats/test-aaaa1111" <<STATE
RIG=test
REPO=https://github.com/acme/demo
ISSUE=70
BRANCH=sgt/test-aaaa1111
WORKTREE=$worktree
SESSION=sgt-test-aaaa1111
DEFAULT_BRANCH=master
STATE

set +e
sgt sweep > "$SGT_ROOT/sweep.out" 2> "$SGT_ROOT/sweep.err"
sweep_rc=$?
set -e

if [[ "$sweep_rc" -ne 0 ]]; then
  echo "expected sweep to succeed for completed polecat cleanup path, got exit $sweep_rc" >&2
  exit 1
fi

if [[ -s "$SGT_ROOT/sweep.err" ]]; then
  echo "expected no stderr for successful sweep path" >&2
  cat "$SGT_ROOT/sweep.err" >&2
  exit 1
fi

if ! grep -q "completed (PR OPEN) — cleaning up" "$SGT_ROOT/sweep.out"; then
  echo "expected explicit cleanup line in sweep output" >&2
  cat "$SGT_ROOT/sweep.out" >&2
  exit 1
fi

if ! grep -q "swept 1 completed polecat(s)" "$SGT_ROOT/sweep.out"; then
  echo "expected final sweep summary line" >&2
  cat "$SGT_ROOT/sweep.out" >&2
  exit 1
fi

if [[ -f "$SGT_ROOT/.sgt/polecats/test-aaaa1111" ]]; then
  echo "expected polecat state file to be removed after successful sweep" >&2
  exit 1
fi

if [[ -d "$worktree" ]]; then
  echo "expected polecat worktree to be removed after successful sweep" >&2
  exit 1
fi
'

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail

worktree="$SGT_ROOT/polecats/test-race1111"
mkdir -p "$worktree"
cat > "$SGT_ROOT/.sgt/polecats/test-race1111" <<STATE
RIG=test
REPO=https://github.com/acme/demo
ISSUE=71
BRANCH=sgt/test-race1111
WORKTREE=$worktree
SESSION=sgt-test-race1111
DEFAULT_BRANCH=master
STATE

set +e
SGT_TEST_GH_MODE=lookup_race sgt sweep > "$SGT_ROOT/sweep-race.out" 2> "$SGT_ROOT/sweep-race.err"
sweep_rc=$?
set -e

if [[ "$sweep_rc" -ne 0 ]]; then
  echo "expected sweep to recover from lookup race and succeed, got exit $sweep_rc" >&2
  exit 1
fi

if [[ -s "$SGT_ROOT/sweep-race.err" ]]; then
  echo "expected no stderr for resilient lookup-race cleanup path" >&2
  cat "$SGT_ROOT/sweep-race.err" >&2
  exit 1
fi

if ! grep -q "completed (fallback: reason_code=sweep-pr-lookup-race-issue-closed) — cleaning up" "$SGT_ROOT/sweep-race.out"; then
  echo "expected explicit fallback cleanup line in sweep output" >&2
  cat "$SGT_ROOT/sweep-race.out" >&2
  exit 1
fi

if ! grep -q "swept 1 completed polecat(s)" "$SGT_ROOT/sweep-race.out"; then
  echo "expected final sweep summary line for fallback cleanup path" >&2
  cat "$SGT_ROOT/sweep-race.out" >&2
  exit 1
fi

if [[ -f "$SGT_ROOT/.sgt/polecats/test-race1111" ]]; then
  echo "expected lookup-race fallback cleanup to remove polecat state file" >&2
  exit 1
fi

if [[ -d "$worktree" ]]; then
  echo "expected lookup-race fallback cleanup to remove polecat worktree" >&2
  exit 1
fi

if ! grep -q "SWEEP_RESILIENT_CLEANUP reason_code=sweep-pr-lookup-race-issue-closed polecat=test-race1111" "$SGT_ROOT/sgt.log"; then
  echo "expected sweep resilient cleanup activity log entry" >&2
  cat "$SGT_ROOT/sgt.log" >&2
  exit 1
fi

if ! grep -q "MAYOR POLECAT CLEANUP reason_code=sweep-pr-lookup-race-issue-closed polecat=test-race1111" "$SGT_ROOT/.sgt/mayor-decisions.log"; then
  echo "expected decision-log reason code for fallback cleanup path" >&2
  cat "$SGT_ROOT/.sgt/mayor-decisions.log" >&2
  exit 1
fi
'

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail

cat > "$SGT_ROOT/.sgt/polecats/test-badstate" <<STATE
RIG=test
REPO=https://github.com/acme/demo
ISSUE=70
BRANCH=sgt/test-badstate
WORKTREE=$SGT_ROOT/polecats/test-badstate
DEFAULT_BRANCH=master
STATE

set +e
sgt sweep > "$SGT_ROOT/sweep-bad.out" 2> "$SGT_ROOT/sweep-bad.err"
sweep_rc=$?
set -e

if [[ "$sweep_rc" -eq 0 ]]; then
  echo "expected sweep to fail on invalid polecat state missing SESSION" >&2
  exit 1
fi

if ! grep -q "missing SESSION in polecat state" "$SGT_ROOT/sweep-bad.err"; then
  echo "expected actionable missing SESSION error text" >&2
  cat "$SGT_ROOT/sweep-bad.err" >&2
  exit 1
fi
'

echo "ALL TESTS PASSED"
