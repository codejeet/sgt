#!/usr/bin/env bash
# test_refinery_stale_queue_item.sh — Regression checks for refinery pre-merge reviewed-head stale guard.

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
      echo "Pre-merge stale-head guard regression PR"
      ;;
    state)
      echo "OPEN"
      ;;
    mergeable)
      echo "MERGEABLE"
      ;;
    state,headRefOid)
      call_n="$(inc_file "$STATE_HEAD_CALLS_FILE")"
      if [[ "$MODE" == "stale_race" ]]; then
        if [[ "$call_n" -eq 1 ]]; then
          echo "OPEN|reviewed111"
        else
          echo "OPEN|live222"
        fi
      else
        echo "OPEN|stable111"
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
  chmod +x "$mock_bin/gh"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_MODE="$mode" \
    SGT_MOCK_MERGE_CALLS="$merge_calls" \
    SGT_MOCK_STATE_HEAD_CALLS="$state_head_calls" \
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
HEAD_SHA=queued111
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
    stale_race)
      if [[ -s "$merge_calls" ]]; then
        if [[ "$(cat "$merge_calls")" != "" && "$(cat "$merge_calls")" != "0" ]]; then
          echo "expected no merge attempt for stale_race" >&2
          return 1
        fi
      fi
      if ! grep -q 'pre-merge stale-head guard — skipping (reviewed=reviewed111 live=live222)' "$home_dir/sgt/refinery.out"; then
        echo "expected stale-head guard skip output for stale_race" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_PREMERGE_SKIP pr=#123 reason_code=stale-reviewed-head reviewed_head=reviewed111 live_head=live222' "$home_dir/sgt/sgt.log"; then
        echo "expected structured stale-reviewed-head telemetry" >&2
        return 1
      fi
      if ! grep -q '^HEAD_SHA=live222$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected queue HEAD_SHA refresh to live222 on stale_race" >&2
        return 1
      fi
      if ! grep -q '^REVIEWED_HEAD_SHA=reviewed111$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected queue REVIEWED_HEAD_SHA to persist reviewed111 on stale_race" >&2
        return 1
      fi
      if ! grep -Eq '^REVIEWED_AT=[0-9]+$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected queue REVIEWED_AT to be persisted on stale_race" >&2
        return 1
      fi
      if [[ "$(cat "$state_head_calls")" != "2" ]]; then
        echo "expected exactly 2 state/head lookups for stale_race" >&2
        return 1
      fi
      ;;
    normal_flow)
      if [[ "$(cat "$merge_calls")" != "1" ]]; then
        echo "expected exactly 1 merge attempt for normal_flow" >&2
        return 1
      fi
      if grep -q 'REFINERY_PREMERGE_SKIP pr=#123' "$home_dir/sgt/sgt.log"; then
        echo "did not expect pre-merge skip telemetry for normal_flow" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_MERGED pr=#123 issue=#77' "$home_dir/sgt/sgt.log"; then
        echo "expected merged telemetry for normal_flow" >&2
        return 1
      fi
      if [[ "$(cat "$state_head_calls")" != "2" ]]; then
        echo "expected exactly 2 state/head lookups for normal_flow" >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported mode: $mode" >&2
      return 1
      ;;
  esac
}

run_case stale_race
run_case normal_flow

echo "ALL TESTS PASSED"
