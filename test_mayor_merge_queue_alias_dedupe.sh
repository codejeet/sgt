#!/usr/bin/env bash
# test_mayor_merge_queue_alias_dedupe.sh — Regression check for repo+PR queue-key dedupe across alias names.

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

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  echo "#84 [sgt-pr84]"
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
    body) echo "Closes #12" ;;
    mergeable) echo "MERGEABLE" ;;
    headRefOid) echo "head84abc" ;;
    state) echo "OPEN" ;;
    *) echo "" ;;
  esac
  exit 0
fi

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
    *) echo "" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  # Mayor critical/high scan should see no alertable issues.
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == "graphql" ]]; then
  echo "0|0"
  exit 0
fi

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "has-session" ]]; then
  # Keep mayor from trying to restart daemon/deacon/witness/refinery.
  exit 0
fi

if [[ "${1:-}" == "new-session" || "${1:-}" == "kill-session" ]]; then
  exit 0
fi

echo "mock tmux unsupported: $*" >&2
exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_MAYOR_INTERVAL=1 \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/sgt"

cat > "$SGT_ROOT/.sgt/deacon-heartbeat.json" <<HB
{
  "timestamp": "$(date -Iseconds)",
  "cycle": 1,
  "pid": $$
}
HB

mkdir -p "$SGT_ROOT/.sgt/merge-queue"
cat > "$SGT_ROOT/.sgt/merge-queue/sgt-691e731c" <<MQ
POLECAT=sgt-691e731c
RIG=sgt
REPO=https://github.com/acme/demo
BRANCH=sgt/sgt-691e731c
ISSUE=12
PR=84
HEAD_SHA=head84abc
AUTO_MERGE=true
TYPE=polecat
REVIEW_STATE=REVIEW_PENDING
REVIEW_UPDATED_AT=$(date +%s)
REVIEW_UNCLEAR_SINCE=
QUEUED=$(date -Iseconds)
MQ

# Run mayor briefly; it will try to queue orphan PR #84 using sgt-pr84 alias.
sgt _mayor > "$SGT_ROOT/mayor.out" 2>&1 &
mayor_pid=$!

# Wait until duplicate queue-key telemetry appears (or timeout) before stopping mayor.
for _ in $(seq 1 40); do
  if grep -q "duplicate queue skipped — reason_code=duplicate-queue-key" "$SGT_ROOT/mayor.out" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

kill "$mayor_pid" 2>/dev/null || true
for _ in 1 2 3 4 5; do
  if ! kill -0 "$mayor_pid" 2>/dev/null; then
    break
  fi
  sleep 0.2
done
if kill -0 "$mayor_pid" 2>/dev/null; then
  kill -9 "$mayor_pid" 2>/dev/null || true
fi
wait "$mayor_pid" 2>/dev/null || true
'

OUT_FILE="$HOME_DIR/sgt/mayor.out"
if ! grep -q 'duplicate queue skipped — reason_code=duplicate-queue-key' "$OUT_FILE"; then
  echo "expected duplicate queue-key skip status line in mayor output" >&2
  exit 1
fi

LOG_FILE="$HOME_DIR/sgt/sgt.log"
if ! grep -q 'MERGE_QUEUE_DUPLICATE_SKIP rig=sgt repo=acme/demo pr=#84 reason_code=duplicate-queue-key' "$LOG_FILE"; then
  echo "expected merge-queue duplicate skip observability log event" >&2
  exit 1
fi

QUEUE_DIR="$HOME_DIR/sgt/.sgt/merge-queue"
queue_count="$(find "$QUEUE_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
if [[ "$queue_count" != "1" ]]; then
  echo "expected one queue item after alias dedupe, got $queue_count" >&2
  exit 1
fi

if [[ -f "$QUEUE_DIR/sgt-pr84" ]]; then
  echo "expected no secondary alias queue entry (sgt-pr84)" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
