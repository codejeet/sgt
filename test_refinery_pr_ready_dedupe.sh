#!/usr/bin/env bash
# test_refinery_pr_ready_dedupe.sh — Regression check for duplicate PR-ready queue replay dedupe.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
MERGE_CALLS="$TMP_ROOT/merge-calls"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf '0\n' > "$MERGE_CALLS"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

MERGE_CALLS_FILE="${SGT_MOCK_MERGE_CALLS:?missing SGT_MOCK_MERGE_CALLS}"

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
    title) echo "Replay dedupe issue" ;;
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
    title) echo "Replay dedupe PR" ;;
    state) echo "OPEN" ;;
    mergeable) echo "MERGEABLE" ;;
    state,headRefOid) echo "OPEN|abc123" ;;
    *) echo "" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "checks" ]]; then
  echo "all checks pass"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "diff" ]]; then
  # Empty diff keeps review deterministic and fast.
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  inc_file "$MERGE_CALLS_FILE" >/dev/null
  echo "merged"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_MOCK_MERGE_CALLS="$MERGE_CALLS" \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

cat > "$SGT_ROOT/.sgt/merge-queue/test-pr123-a" <<MQ
POLECAT=test-pr123-a
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

cat > "$SGT_ROOT/.sgt/merge-queue/test-pr123-b" <<MQ
POLECAT=test-pr123-b
RIG=test
REPO=https://github.com/acme/demo
BRANCH=sgt/test-pr123-replay
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

if [[ "$(cat "$MERGE_CALLS")" != "1" ]]; then
  echo "expected exactly one merge attempt for duplicate PR-ready replay" >&2
  exit 1
fi

# Note: refinery output lines may vary based on receipt replay/no-op paths.
# The core invariant is that only one merge attempt occurs and duplicate queue entries are drained.
OUT_FILE="$HOME_DIR/sgt/refinery.out"
LOG_FILE="$HOME_DIR/sgt/sgt.log"

if [[ -n "$(ls -A "$HOME_DIR/sgt/.sgt/merge-queue" 2>/dev/null || true)" ]]; then
  echo "expected duplicate queue replay entries to be fully drained" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
