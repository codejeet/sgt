#!/usr/bin/env bash
# Regression: merge-in-progress should be treated as in-flight, not as a scary merge failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
MERGE_CALLS="$TMP_ROOT/merge-calls"
MERGE_COMMIT_CALLS="$TMP_ROOT/merge-commit-calls"
COMMENT_CALLS="$TMP_ROOT/comment-calls"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf '0\n' > "$MERGE_CALLS"
printf '0\n' > "$MERGE_COMMIT_CALLS"
printf '0\n' > "$COMMENT_CALLS"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

MERGE_CALLS_FILE="${SGT_MOCK_MERGE_CALLS:?missing SGT_MOCK_MERGE_CALLS}"
MERGE_COMMIT_CALLS_FILE="${SGT_MOCK_MERGE_COMMIT_CALLS:?missing SGT_MOCK_MERGE_COMMIT_CALLS}"
COMMENT_CALLS_FILE="${SGT_MOCK_COMMENT_CALLS:?missing SGT_MOCK_COMMENT_CALLS}"

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
      --json) json_fields="${2:-}"; shift 2 ;;
      --jq) shift 2 ;;
      --repo) shift 2 ;;
      *) shift ;;
    esac
  done
  case "$json_fields" in
    labels) echo "sgt-authorized" ;;
    state) echo "OPEN" ;;
    title) echo "Merge in progress issue" ;;
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
      --json) json_fields="${2:-}"; shift 2 ;;
      --jq) shift 2 ;;
      --repo) shift 2 ;;
      *) shift ;;
    esac
  done
  case "$json_fields" in
    title)
      echo "Merge in progress PR"
      ;;
    state)
      call_n="$(cat "$MERGE_COMMIT_CALLS_FILE" 2>/dev/null || echo 0)"
      if [[ "$call_n" -ge 1 ]]; then
        echo "MERGED"
      else
        echo "OPEN"
      fi
      ;;
    mergeable)
      echo "MERGEABLE"
      ;;
    state,headRefOid)
      echo "OPEN|live111"
      ;;
    state,mergeCommit)
      inc_file "$MERGE_COMMIT_CALLS_FILE" >/dev/null
      echo "OPEN|"
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

if [[ "${1:-}" == "pr" && "${2:-}" == "diff" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  inc_file "$MERGE_CALLS_FILE" >/dev/null
  echo "GraphQL: Pull Request is already being merged" >&2
  exit 1
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  inc_file "$COMMENT_CALLS_FILE" >/dev/null
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  inc_file "$COMMENT_CALLS_FILE" >/dev/null
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  if [[ "${2:-}" == "repos/acme/demo/branches/sgt%2Ftest-pr123" ]]; then
    echo "Not Found" >&2
    exit 1
  fi
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
  SGT_MOCK_MERGE_COMMIT_CALLS="$MERGE_COMMIT_CALLS" \
  SGT_MOCK_COMMENT_CALLS="$COMMENT_CALLS" \
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
HEAD_SHA=live111
AUTO_MERGE=true
TYPE=polecat
QUEUED=$(date -Iseconds)
MQ

run_pass() {
  local out="$1"
  timeout 6 sgt _refinery test > "$out" 2>&1 &
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
}

run_pass "$SGT_ROOT/refinery-pass1.out"
run_pass "$SGT_ROOT/refinery-pass2.out"
'

grep -q 'merge already in flight — awaiting live confirmation' "$HOME_DIR/sgt/refinery-pass1.out" || {
  echo "expected merge-in-flight message on first pass" >&2
  exit 1
}

grep -q 'PR #123 already merged — cleaning up' "$HOME_DIR/sgt/refinery-pass2.out" || {
  echo "expected later self-heal cleanup once live state converged" >&2
  exit 1
}

if grep -q 'merge failed:' "$HOME_DIR/sgt/refinery-pass1.out"; then
  echo "did not expect scary merge failed output for merge-in-progress" >&2
  exit 1
fi

grep -q 'REFINERY_MERGE_IN_FLIGHT pr=#123 issue=#77 class=merge-in-progress' "$HOME_DIR/sgt/sgt.log" || {
  echo "expected structured merge-in-flight log entry" >&2
  exit 1
}

if [[ "$(cat "$COMMENT_CALLS")" != "0" ]]; then
  echo "expected no PR/issue comments for merge-in-progress self-heal" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
