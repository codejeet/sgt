#!/usr/bin/env bash
# test_refinery_conflict_resling_guardrail.sh - Regression checks for durable conflict evidence + single-active resling replay guardrail.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
TMUX_NEW_SESSION_COUNT="$TMP_ROOT/tmux-new-session-count"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf '0\n' > "$TMUX_NEW_SESSION_COUNT"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

mode="${SGT_MOCK_MODE:-phase_a}"

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
      echo "Conflict replay issue"
      ;;
    state)
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
      echo "Conflict PR"
      ;;
    state)
      echo "OPEN"
      ;;
    mergeable)
      echo "CONFLICTING"
      ;;
    state,mergeable)
      echo "OPEN|MERGEABLE"
      ;;
    state,headRefOid)
      echo "OPEN|abc123"
      ;;
    headRefOid)
      echo "abc123"
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
    # Keep first claimant in-flight long enough for second refinery process to contend on resling claim.
    sleep 1
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
  SGT_MOCK_MODE=phase_a \
  SGT_MOCK_TMUX_NEW_SESSION_COUNT="$TMUX_NEW_SESSION_COUNT" \
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
HEAD_SHA=head123
AUTO_MERGE=true
TYPE=polecat
BACKEND=codex
QUEUED=$(date -Iseconds)
MQ

cat > "$SGT_ROOT/.sgt/merge-queue/test-pr124" <<MQ
POLECAT=test-pr124
RIG=test
REPO=https://github.com/acme/demo
BRANCH=sgt/test-pr124
ISSUE=77
PR=124
HEAD_SHA=head124
AUTO_MERGE=true
TYPE=polecat
BACKEND=codex
QUEUED=$(date -Iseconds)
MQ

timeout 7 sgt _refinery test > "$SGT_ROOT/refinery-a1.out" 2>&1 &
pid1=$!
sleep 0.1
timeout 7 sgt _refinery test > "$SGT_ROOT/refinery-a2.out" 2>&1 &
pid2=$!

for _ in $(seq 1 120); do
  fifo="$SGT_ROOT/.sgt/refinery-test.fifo"
  if [[ -p "$fifo" ]]; then
    printf "test-wake\n" > "$fifo"
    break
  fi
  sleep 0.05
done

wait "$pid1" || true
wait "$pid2" || true

# Prepare restart replay from durable pending evidence with queue already drained.
cat > "$SGT_ROOT/.sgt/refinery-conflicts/restart.state" <<EV
KEY=acme/demo|issue=88
RIG=test
REPO=https://github.com/acme/demo
ISSUE=88
ORIGIN_PR=188
ORIGIN_HEAD_SHA=head188
ORIGIN_ATTEMPT_KEY=acme/demo|pr=188|head=head188
ORIGIN_TS=$(date +%s)
ORIGIN_AT=$(date -Iseconds)
CONFLICT_COUNT=1
STATUS=PENDING
SOURCE_EVENT=refinery-conflict
SOURCE_EVENT_KEY=refinery-conflict:test-pr188:#188
BACKEND=codex
RESLING_DISPATCHED_POLECAT=
LAST_OUTCOME=conflict-recorded
LAST_REASON=merge conflict detected
EV

# Restart pass 1: should replay pending evidence and dispatch exactly one new polecat.
timeout 7 sgt _refinery test > "$SGT_ROOT/refinery-b1.out" 2>&1 &
pid3=$!
for _ in $(seq 1 120); do
  fifo="$SGT_ROOT/.sgt/refinery-test.fifo"
  if [[ -p "$fifo" ]]; then
    printf "test-wake\n" > "$fifo"
    break
  fi
  sleep 0.05
done
wait "$pid3" || true

# Restart pass 2: same evidence should not dispatch a duplicate.
timeout 7 sgt _refinery test > "$SGT_ROOT/refinery-b2.out" 2>&1 &
pid4=$!
for _ in $(seq 1 120); do
  fifo="$SGT_ROOT/.sgt/refinery-test.fifo"
  if [[ -p "$fifo" ]]; then
    printf "test-wake\n" > "$fifo"
    break
  fi
  sleep 0.05
done
wait "$pid4" || true
'

spawn_count="$(cat "$TMUX_NEW_SESSION_COUNT" 2>/dev/null || echo 0)"
if [[ "$spawn_count" != "2" ]]; then
  echo "expected exactly two total polecat spawns (one from concurrent conflicts, one from restart replay), got $spawn_count" >&2
  exit 1
fi

EVIDENCE_FILES="$(ls "$HOME_DIR/sgt/.sgt/refinery-conflicts"/*.state 2>/dev/null || true)"
if [[ -z "$EVIDENCE_FILES" ]]; then
  echo "expected conflict evidence files to exist" >&2
  exit 1
fi

PRIMARY_EVIDENCE="$(grep -l '^ISSUE=77$' "$HOME_DIR/sgt/.sgt/refinery-conflicts"/*.state 2>/dev/null | head -1 || true)"
if [[ -z "$PRIMARY_EVIDENCE" ]]; then
  echo "expected conflict evidence for issue #77" >&2
  exit 1
fi
if ! grep -q '^ORIGIN_PR=123\|^ORIGIN_PR=124' "$PRIMARY_EVIDENCE"; then
  echo "expected durable conflict evidence to persist original PR context" >&2
  exit 1
fi
if ! grep -q '^ORIGIN_HEAD_SHA=head' "$PRIMARY_EVIDENCE"; then
  echo "expected durable conflict evidence to persist original head context" >&2
  exit 1
fi
if ! grep -q '^ORIGIN_ATTEMPT_KEY=' "$PRIMARY_EVIDENCE"; then
  echo "expected durable conflict evidence to persist merge attempt key" >&2
  exit 1
fi
if ! grep -q '^ORIGIN_TS=' "$PRIMARY_EVIDENCE"; then
  echo "expected durable conflict evidence to persist origin timestamp" >&2
  exit 1
fi

RESTART_EVIDENCE="$HOME_DIR/sgt/.sgt/refinery-conflicts/restart.state"
if ! grep -q '^STATUS=RESLING_DISPATCHED' "$RESTART_EVIDENCE"; then
  echo "expected restart replay evidence to transition to RESLING_DISPATCHED" >&2
  exit 1
fi

OUT_A1="$HOME_DIR/sgt/refinery-a1.out"
OUT_A2="$HOME_DIR/sgt/refinery-a2.out"
if ! grep -q 'conflict evidence recorded for issue #77' "$OUT_A1" && ! grep -q 'conflict evidence recorded for issue #77' "$OUT_A2"; then
  echo "expected operator-visible conflict evidence telemetry in refinery output" >&2
  exit 1
fi

LOG_FILE="$HOME_DIR/sgt/sgt.log"
if ! grep -q 'REFINERY_CONFLICT_EVIDENCE_WRITTEN pr=#123\|REFINERY_CONFLICT_EVIDENCE_WRITTEN pr=#124' "$LOG_FILE"; then
  echo "expected structured conflict evidence event in log" >&2
  exit 1
fi
if ! grep -q 'REFINERY_CONFLICT_RESLING_DEDUPE issue=#77 .*reason_code=' "$LOG_FILE"; then
  echo "expected structured concurrent resling dedupe event in log" >&2
  exit 1
fi
if ! grep -q 'REFINERY_CONFLICT_RESLING_RESUMED issue=#88' "$LOG_FILE"; then
  echo "expected structured restart replay resume event in log" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
