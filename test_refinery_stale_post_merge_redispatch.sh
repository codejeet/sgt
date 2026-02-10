#!/usr/bin/env bash
# test_refinery_stale_post_merge_redispatch.sh — Regression check for stale post-merge redispatch guard.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
PR_STATE_CALLS="$TMP_ROOT/pr-state-calls"
ISSUE_STATE_CALLS="$TMP_ROOT/issue-state-calls"
TMUX_NEW_SESSION_MARKER="$TMP_ROOT/tmux-new-session"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
: > "$PR_STATE_CALLS"
: > "$ISSUE_STATE_CALLS"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

PR_STATE_CALLS_FILE="${SGT_MOCK_PR_STATE_CALLS:?missing SGT_MOCK_PR_STATE_CALLS}"
ISSUE_STATE_CALLS_FILE="${SGT_MOCK_ISSUE_STATE_CALLS:?missing SGT_MOCK_ISSUE_STATE_CALLS}"

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
    labels)
      echo "sgt-authorized"
      ;;
    title)
      echo "Stale post-merge redispatch issue"
      ;;
    state)
      # Simulate issue being reopened by stale handler; PR state must still block redispatch.
      inc_file "$ISSUE_STATE_CALLS_FILE" >/dev/null
      echo "OPEN"
      ;;
    body)
      echo "Issue body"
      ;;
    *)
      echo ""
      ;;
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
      echo "Stale post-merge redispatch PR"
      ;;
    state)
      inc_file "$PR_STATE_CALLS_FILE" >/dev/null
      echo "OPEN"
      ;;
    mergeable)
      echo "CONFLICTING"
      ;;
    state,mergeable)
      call_n="$(inc_file "$PR_STATE_CALLS_FILE")"
      if [[ "$call_n" -le 2 ]]; then
        echo "OPEN|MERGEABLE"
      else
        echo "MERGED|MERGEABLE"
      fi
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

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "close" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "reopen" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

MARKER="${SGT_MOCK_TMUX_NEW_SESSION_MARKER:?missing SGT_MOCK_TMUX_NEW_SESSION_MARKER}"

if [[ "${1:-}" == "new-session" ]]; then
  touch "$MARKER"
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
  SGT_MOCK_PR_STATE_CALLS="$PR_STATE_CALLS" \
  SGT_MOCK_ISSUE_STATE_CALLS="$ISSUE_STATE_CALLS" \
  SGT_MOCK_TMUX_NEW_SESSION_MARKER="$TMUX_NEW_SESSION_MARKER" \
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
QUEUED=$(date -Iseconds)
MQ

timeout 6 sgt _refinery test > "$SGT_ROOT/refinery.out" 2>&1 &
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

OUT_FILE="$HOME_DIR/sgt/refinery.out"
LOG_FILE="$HOME_DIR/sgt/sgt.log"

if [[ -f "$TMUX_NEW_SESSION_MARKER" ]]; then
  echo "expected stale post-merge redispatch to skip spawning a new polecat" >&2
  exit 1
fi

if ! grep -q 'dispatch-instant gate (refinery-conflict)' "$OUT_FILE"; then
  echo "expected dispatch-instant gate skip message in refinery output" >&2
  exit 1
fi

if ! grep -q 'source PR #123 state=MERGED' "$OUT_FILE"; then
  echo "expected final gate skip reason to include merged source PR state" >&2
  exit 1
fi

if [[ "$(cat "$ISSUE_STATE_CALLS" 2>/dev/null || echo 0)" -lt 2 ]]; then
  echo "expected issue-state revalidation at both stale check and dispatch-instant gate" >&2
  exit 1
fi

if [[ "$(cat "$PR_STATE_CALLS" 2>/dev/null || echo 0)" -lt 3 ]]; then
  echo "expected source PR state to be checked for queue pass, stale check, and dispatch-instant gate" >&2
  exit 1
fi

if ! grep -q 'RESLING_SKIP_FINAL_GATE issue=#77 rig=test source_event=refinery-conflict source_event_key="refinery-conflict:test-pr123:#123" source_pr=123 skip_reason="source PR #123 state=MERGED"' "$LOG_FILE"; then
  echo "expected structured final-gate skip entry with source event key and reason in activity log" >&2
  exit 1
fi

if [[ -n "$(ls -A "$HOME_DIR/sgt/.sgt/polecats" 2>/dev/null || true)" ]]; then
  echo "expected no new polecat state files after stale post-merge skip" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
