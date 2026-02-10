#!/usr/bin/env bash
# test_refinery_merge_retry_auto_guardrail.sh — Regression checks for branch-policy auto-merge retry guardrail.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

run_case() {
  local mode="$1"
  local tmp_root home_dir mock_bin merge_calls state_head_calls
  tmp_root="$(mktemp -d)"
  trap 'rm -rf "$tmp_root"' RETURN

  home_dir="$tmp_root/home"
  mock_bin="$tmp_root/mockbin"
  merge_calls="$tmp_root/merge-calls"
  state_head_calls="$tmp_root/state-head-calls"
  mkdir -p "$home_dir/.local/bin" "$mock_bin"
  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"
  : > "$merge_calls"
  : > "$state_head_calls"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

MODE="${SGT_MOCK_MODE:?missing SGT_MOCK_MODE}"
MERGE_CALLS_FILE="${SGT_MOCK_MERGE_CALLS:?missing SGT_MOCK_MERGE_CALLS}"
STATE_HEAD_CALLS_FILE="${SGT_MOCK_STATE_HEAD_CALLS:?missing SGT_MOCK_STATE_HEAD_CALLS}"

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
    state) echo "OPEN" ;;
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
      echo "Auto retry guardrail regression PR"
      ;;
    state)
      echo "OPEN"
      ;;
    mergeable)
      echo "MERGEABLE"
      ;;
    state,headRefOid)
      inc_file "$STATE_HEAD_CALLS_FILE" >/dev/null
      echo "OPEN|live111"
      ;;
    state,mergeCommit)
      echo "MERGED|mergeauto123"
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
  call_n="$(inc_file "$MERGE_CALLS_FILE")"
  case "$MODE" in
    auto_required_success)
      if [[ "$call_n" -eq 1 ]]; then
        echo "Branch policy requires auto-merge for this pull request" >&2
        exit 1
      fi
      if [[ "$call_n" -eq 2 && " $* " == *" --auto "* ]]; then
        echo "auto-merge enabled"
        exit 0
      fi
      ;;
    non_retry_unrelated)
      if [[ "$call_n" -eq 1 ]]; then
        echo "merge failed: required review is missing" >&2
        exit 1
      fi
      ;;
    duplicate_event_suppression)
      if [[ "$call_n" -eq 1 ]]; then
        echo "Branch policy requires auto-merge for this pull request" >&2
        exit 1
      fi
      if [[ "$call_n" -eq 2 && " $* " == *" --auto "* ]]; then
        echo "auto-merge enabled"
        exit 0
      fi
      ;;
  esac
  echo "unexpected merge call #$call_n mode=$MODE args=$*" >&2
  exit 2
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
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
  chmod +x "$mock_bin/gh"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_MODE="$mode" \
    SGT_MOCK_MERGE_CALLS="$merge_calls" \
    SGT_MOCK_STATE_HEAD_CALLS="$state_head_calls" \
    SGT_REFINERY_MERGE_MAX_ATTEMPTS=3 \
    SGT_REFINERY_MERGE_RETRY_BASE_MS=0 \
    SGT_REFINERY_MERGE_RETRY_JITTER_MS=0 \
    bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

queue_once() {
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
}

run_refinery() {
  timeout 6 sgt _refinery test > "$1" 2>&1 &
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

queue_once
run_refinery "$SGT_ROOT/refinery-pass1.out"

if [[ "$SGT_MOCK_MODE" == "duplicate_event_suppression" ]]; then
  queue_once
  run_refinery "$SGT_ROOT/refinery-pass2.out"
fi
'

  case "$mode" in
    auto_required_success)
      if [[ "$(cat "$merge_calls")" != "2" ]]; then
        echo "expected 2 merge calls for auto_required_success" >&2
        return 1
      fi
      if ! grep -q 'merge failed due to branch policy requiring auto-merge — retrying once with --auto' "$home_dir/sgt/refinery-pass1.out"; then
        echo "expected visible auto-merge retry message" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_MERGE_RETRY_AUTO repo=acme/demo pr=#123 reason=branch-policy-requires-auto-merge outcome=success' "$home_dir/sgt/sgt.log"; then
        echo "expected structured auto retry success event" >&2
        return 1
      fi
      if [[ -f "$home_dir/sgt/.sgt/merge-queue/test-pr123" ]]; then
        echo "expected queue item to be removed after auto retry success" >&2
        return 1
      fi
      ;;
    non_retry_unrelated)
      if [[ "$(cat "$merge_calls")" != "1" ]]; then
        echo "expected exactly 1 merge call for unrelated non-retry failure" >&2
        return 1
      fi
      if grep -q 'REFINERY_MERGE_RETRY_AUTO repo=acme/demo pr=#123' "$home_dir/sgt/sgt.log"; then
        echo "did not expect auto-retry event for unrelated merge failure" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_MERGE_FAILED pr=#123 attempt=1/3 class=non-transient transient=false' "$home_dir/sgt/sgt.log"; then
        echo "expected standard merge failure event for unrelated failure" >&2
        return 1
      fi
      ;;
    duplicate_event_suppression)
      if [[ "$(cat "$merge_calls")" != "2" ]]; then
        echo "expected exactly 2 merge calls across duplicate replay" >&2
        return 1
      fi
      if ! grep -q 'duplicate merge key already verified — no-op' "$home_dir/sgt/refinery-pass2.out"; then
        echo "expected duplicate verified-success no-op on replay" >&2
        return 1
      fi
      auto_event_count="$(grep -c 'REFINERY_MERGE_RETRY_AUTO repo=acme/demo pr=#123 reason=branch-policy-requires-auto-merge' "$home_dir/sgt/sgt.log" || true)"
      if [[ "$auto_event_count" != "1" ]]; then
        echo "expected exactly one auto-retry event across duplicate replay, got $auto_event_count" >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported mode: $mode" >&2
      return 1
      ;;
  esac
}

run_case auto_required_success
run_case non_retry_unrelated
run_case duplicate_event_suppression

echo "ALL TESTS PASSED"
