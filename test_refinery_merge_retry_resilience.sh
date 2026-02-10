#!/usr/bin/env bash
# test_refinery_merge_retry_resilience.sh — Regression checks for refinery transient merge retries.

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
  echo "sgt-authorized"
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
      echo "Retry resilience regression PR"
      ;;
    state)
      echo "OPEN"
      ;;
    mergeable)
      echo "MERGEABLE"
      ;;
    state,headRefOid)
      call_n="$(inc_file "$STATE_HEAD_CALLS_FILE")"
      if [[ "$MODE" == "drift_retry" && "$call_n" -ge 2 ]]; then
        echo "OPEN|live222"
      else
        echo "OPEN|live111"
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

if [[ "${1:-}" == "pr" && "${2:-}" == "diff" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  call_n="$(inc_file "$MERGE_CALLS_FILE")"
  if [[ "$call_n" -eq 1 ]]; then
    echo "HTTP 502 Bad Gateway: request timed out" >&2
    exit 1
  fi
  if [[ "$MODE" == "transient_success" && "$call_n" -eq 2 ]]; then
    echo "merged"
    exit 0
  fi
  echo "unexpected merge call #$call_n for mode=$MODE" >&2
  exit 2
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

  case "$mode" in
    transient_success)
      if [[ "$(cat "$merge_calls")" != "2" ]]; then
        echo "expected 2 merge attempts for transient_success" >&2
        return 1
      fi
      if ! grep -Eq 'merge transient failure class=(timeout|http-5xx) attempt=1/3 — retrying in 0.000s' "$home_dir/sgt/refinery.out"; then
        echo "expected transient retry message in refinery output" >&2
        return 1
      fi
      if ! grep -Eq 'REFINERY_MERGE_RETRY pr=#123 attempt=1/3 class=(timeout|http-5xx) delay_s=0.000' "$home_dir/sgt/sgt.log"; then
        echo "expected structured retry log event" >&2
        return 1
      fi
      if [[ -f "$home_dir/sgt/.sgt/merge-queue/test-pr123" ]]; then
        echo "expected queue item to be removed after successful retry" >&2
        return 1
      fi
      ;;
    drift_retry)
      if [[ "$(cat "$merge_calls")" != "1" ]]; then
        echo "expected exactly 1 merge attempt before drift-based skip" >&2
        return 1
      fi
      if ! grep -q 'merge retry skipped — head sha drifted expected=live111 live=live222' "$home_dir/sgt/refinery.out"; then
        echo "expected retry drift skip message in refinery output" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_MERGE_RETRY_SKIP pr=#123 attempt=1/3 reason="head sha drifted expected=live111 live=live222"' "$home_dir/sgt/sgt.log"; then
        echo "expected structured retry skip log event" >&2
        return 1
      fi
      if ! grep -q '^HEAD_SHA=live222$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected queue HEAD_SHA refresh after retry drift" >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported mode: $mode" >&2
      return 1
      ;;
  esac
}

run_case transient_success
run_case drift_retry

echo "ALL TESTS PASSED"
