#!/usr/bin/env bash
# Regression: conflict replay must redispatch by issue id when source PR is already closed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
TMUX_NEW_SESSION_COUNT="$TMP_ROOT/tmux-new-session-count"
PR_STATE_CALLS="$TMP_ROOT/pr-state-calls"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf '0\n' > "$TMUX_NEW_SESSION_COUNT"
printf '0\n' > "$PR_STATE_CALLS"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

COUNT_FILE="${SGT_MOCK_PR_STATE_CALLS:?missing SGT_MOCK_PR_STATE_CALLS}"

inc_file() {
  local path="$1"
  local n=0
  if [[ -s "$path" ]]; then
    n="$(cat "$path" 2>/dev/null || echo 0)"
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  n=$((n + 1))
  printf '%s\n' "$n" > "$path"
  echo "$n"
}

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  shift 2
  json_fields=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_fields="${2:-}"
        shift 2
        ;;
      --jq)
        shift 2
        ;;
      --repo)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  case "$json_fields" in
    labels) echo "sgt-authorized" ;;
    title) echo "Conflict replay closed-source PR issue" ;;
    state) echo "OPEN" ;;
    body) echo "Issue body" ;;
    *) echo "" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  shift 2
  json_fields=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_fields="${2:-}"
        shift 2
        ;;
      --jq)
        shift 2
        ;;
      --repo)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  case "$json_fields" in
    title)
      echo "Conflict PR"
      ;;
    state)
      call_n="$(inc_file "$COUNT_FILE")"
      if [[ "$call_n" -eq 1 ]]; then
        echo "OPEN"
      else
        echo "CLOSED"
      fi
      ;;
    mergeable)
      echo "CONFLICTING"
      ;;
    mergeable,isDraft,mergeStateStatus)
      echo "CONFLICTING|false|DIRTY"
      ;;
    state,mergeable)
      echo "CLOSED|MERGEABLE"
      ;;
    *)
      echo ""
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "checks" ]]; then
  echo "all checks pass"
  exit 0
fi

if [[ "${1:-}" == "pr" && ( "${2:-}" == "comment" || "${2:-}" == "close" ) ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && ( "${2:-}" == "reopen" || "${2:-}" == "comment" ) ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

COUNT_FILE="${SGT_MOCK_TMUX_NEW_SESSION_COUNT:?missing SGT_MOCK_TMUX_NEW_SESSION_COUNT}"

inc_file() {
  local path="$1"
  local n=0
  if [[ -s "$path" ]]; then
    n="$(cat "$path" 2>/dev/null || echo 0)"
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  n=$((n + 1))
  printf '%s\n' "$n" > "$path"
  echo "$n"
}

if [[ "${1:-}" == "new-session" ]]; then
  inc_file "$COUNT_FILE" >/dev/null
  exit 0
fi

if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi

exit 0
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

case "${1:-}" in
  fetch)
    exit 0
    ;;
  symbolic-ref)
    echo "refs/remotes/origin/master"
    exit 0
    ;;
  worktree)
    if [[ "${2:-}" == "add" ]]; then
      mkdir -p "${5:-}"
      exit 0
    fi
    if [[ "${2:-}" == "remove" ]]; then
      rm -rf "${4:-}"
      exit 0
    fi
    ;;
  branch)
    exit 0
    ;;
esac

echo "mock git unsupported: $*" >&2
exit 1
GIT
chmod +x "$MOCK_BIN/git"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_MOCK_TMUX_NEW_SESSION_COUNT="$TMUX_NEW_SESSION_COUNT" \
  SGT_MOCK_PR_STATE_CALLS="$PR_STATE_CALLS" \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

cat > "$SGT_ROOT/.sgt/merge-queue/test-pr123" <<MQ
POLECAT=test-pr123
RIG=test
REPO=https://github.com/acme/demo
BRANCH=sgt/test-pr123
ISSUE=77
PR=123
HEAD_SHA=abc123
AUTO_MERGE=true
TYPE=polecat
BACKEND=codex
QUEUED=$(date -Iseconds)
MQ

timeout 7 sgt _refinery test > "$SGT_ROOT/refinery.out" 2>&1 &
pid=$!

for _ in $(seq 1 120); do
  fifo="$SGT_ROOT/.sgt/refinery-test.fifo"
  if [[ -p "$fifo" ]]; then
    printf "test-wake\n" > "$fifo"
    break
  fi
  sleep 0.05
done

wait "$pid" || true
'

if [[ "$(cat "$TMUX_NEW_SESSION_COUNT")" != "1" ]]; then
  echo "expected exactly one re-dispatch polecat spawn after source PR closed" >&2
  exit 1
fi

OUT_FILE="$HOME_DIR/sgt/refinery.out"
LOG_FILE="$HOME_DIR/sgt/sgt.log"

if ! grep -q 'conflict replay source PR #123 is CLOSED — re-dispatching by issue id' "$OUT_FILE"; then
  echo "expected operator-visible source PR bypass message" >&2
  exit 1
fi

if ! grep -q 'REFINERY_CONFLICT_RESLING_SOURCE_PR_BYPASS issue=#77 .*source_pr=#123 .*source_pr_state=CLOSED .*reason_code=source-pr-closed-dispatch-by-issue-id' "$LOG_FILE"; then
  echo "expected structured conflict source-PR bypass telemetry" >&2
  exit 1
fi

if grep -q 'RESLING_SKIP_STALE issue=#77 .*source_pr=123 .*source PR #123 state=CLOSED' "$LOG_FILE"; then
  echo "expected no stale-skip when conflict replay bypasses closed source PR" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
