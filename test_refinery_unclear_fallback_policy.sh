#!/usr/bin/env bash
# test_refinery_unclear_fallback_policy.sh — Regression checks for deterministic REVIEW_UNCLEAR fallback policy.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

run_case() {
  local mode="$1"
  local tmp_root home_dir mock_bin review_calls merge_calls head_calls
  tmp_root="$(mktemp -d)"
  trap 'rm -rf "$tmp_root"' RETURN

  home_dir="$tmp_root/home"
  mock_bin="$tmp_root/mockbin"
  review_calls="$tmp_root/review-calls"
  merge_calls="$tmp_root/merge-calls"
  head_calls="$tmp_root/head-calls"

  mkdir -p "$home_dir/.local/bin" "$mock_bin"
  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"
  : > "$review_calls"
  : > "$merge_calls"
  : > "$head_calls"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

MODE="${SGT_MOCK_MODE:?missing SGT_MOCK_MODE}"
MERGE_CALLS_FILE="${SGT_MOCK_MERGE_CALLS:?missing SGT_MOCK_MERGE_CALLS}"
HEAD_CALLS_FILE="${SGT_MOCK_HEAD_CALLS:?missing SGT_MOCK_HEAD_CALLS}"

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
    title) echo "Fallback issue" ;;
    body) echo "Fallback issue body" ;;
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
      echo "Fallback regression PR"
      ;;
    body)
      echo "PR body"
      ;;
    state)
      echo "OPEN"
      ;;
    mergeable)
      echo "MERGEABLE"
      ;;
    state,headRefOid)
      call_n="$(inc_file "$HEAD_CALLS_FILE")"
      if [[ "$MODE" == "stale_head_resync" && "$call_n" -ge 1 ]]; then
        echo "OPEN|live222"
      else
        echo "OPEN|live111"
      fi
      ;;
    state,mergeCommit)
      echo "MERGED|mergeabc123"
      ;;
    *)
      echo ""
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "checks" ]]; then
  if [[ "$MODE" == "checks_missing_hold" ]]; then
    echo "no checks reported"
  else
    echo "all checks pass"
  fi
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "diff" ]]; then
  echo "diff --git a/file.txt b/file.txt"
  echo "+change"
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

  cat > "$mock_bin/_ai_promptfile" <<'AIPROMPT'
#!/usr/bin/env bash
set -euo pipefail

MODE="${SGT_MOCK_MODE:?missing SGT_MOCK_MODE}"
REVIEW_CALLS_FILE="${SGT_MOCK_REVIEW_CALLS:?missing SGT_MOCK_REVIEW_CALLS}"

n=0
if [[ -s "$REVIEW_CALLS_FILE" ]]; then
  n="$(cat "$REVIEW_CALLS_FILE" 2>/dev/null || echo 0)"
fi
[[ "$n" =~ ^[0-9]+$ ]] || n=0
n=$((n + 1))
printf '%s\n' "$n" > "$REVIEW_CALLS_FILE"

  case "$MODE" in
    empty_green_mergeable|checks_missing_hold|stale_head_resync)
    # REVIEW_UNCLEAR missing contract output.
    printf ''
    ;;
  timeout_green_mergeable)
    # Simulate timeout classification.
    exit 124
    ;;
  explicit_error_gate_hold)
    cat <<'OUT'
VERDICT: APPROVE
VERDICT: REJECT
OUT
    ;;
  *)
    echo "unsupported mode: $MODE" >&2
    exit 1
    ;;
esac
AIPROMPT
  chmod +x "$mock_bin/_ai_promptfile"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_AI_BACKEND=claude \
    SGT_MOCK_MODE="$mode" \
    SGT_MOCK_REVIEW_CALLS="$review_calls" \
    SGT_MOCK_MERGE_CALLS="$merge_calls" \
    SGT_MOCK_HEAD_CALLS="$head_calls" \
    SGT_REFINERY_REVIEW_UNCLEAR_MAX_RETRIES=1 \
    SGT_REFINERY_REVIEW_UNCLEAR_BACKOFF_BASE_SECS=0 \
    SGT_REFINERY_REVIEW_UNCLEAR_JITTER_SECS=0 \
    SGT_REFINERY_MERGE_MAX_ATTEMPTS=1 \
    SGT_REFINERY_MERGE_RETRY_BASE_MS=0 \
    SGT_REFINERY_MERGE_RETRY_JITTER_MS=0 \
    bash --noprofile --norc -c '
set -euo pipefail

run_refinery_pass() {
  local label="$1"
  timeout 6 sgt _refinery test > "$SGT_ROOT/refinery-${label}.out" 2>&1 &
  local pid=$!
  for _ in $(seq 1 120); do
    local fifo="$SGT_ROOT/.sgt/refinery-test.fifo"
    if [[ -p "$fifo" ]]; then
      printf "test-wake\n" > "$fifo"
      break
    fi
    sleep 0.05
  done
  wait "$pid" || true
}

force_retry_now() {
  local queue_file="$SGT_ROOT/.sgt/merge-queue/test-pr123"
  if [[ -f "$queue_file" ]]; then
    sed -i -E "s/^REVIEW_UNCLEAR_NEXT_RETRY_AT=.*/REVIEW_UNCLEAR_NEXT_RETRY_AT=0/" "$queue_file"
  fi
}

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
REVIEW_STATE=REVIEW_PENDING
REVIEW_UPDATED_AT=$(date +%s)
REVIEW_UNCLEAR_SINCE=
REVIEW_UNCLEAR_RETRY_COUNT=0
REVIEW_UNCLEAR_NEXT_RETRY_AT=0
REVIEW_UNCLEAR_LAST_REASON=
REVIEW_UNCLEAR_LAST_CLASS=
REVIEW_UNCLEAR_ESCALATED=0
REVIEW_UNCLEAR_ESCALATED_AT=
REVIEWED_HEAD_SHA=
REVIEWED_AT=
QUEUED=$(date -Iseconds)
MQ

run_refinery_pass pass1
force_retry_now
run_refinery_pass pass2
'

  case "$mode" in
    empty_green_mergeable)
      if [[ "$(cat "$review_calls")" != "1" ]]; then
        echo "expected one review attempt before fallback merge in empty_green_mergeable" >&2
        return 1
      fi
      if [[ "$(cat "$merge_calls")" != "1" ]]; then
        echo "expected one merge attempt after fallback in empty_green_mergeable" >&2
        return 1
      fi
      if [[ -f "$home_dir/sgt/.sgt/merge-queue/test-pr123" ]]; then
        echo "expected queue cleanup after fallback merge in empty_green_mergeable" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_REVIEW_UNCLEAR_FALLBACK_DECISION pr=#123 issue=#77 attempts=1/1 eligible=1' "$home_dir/sgt/sgt.log"; then
        echo "expected structured fallback-eligible decision for empty output" >&2
        return 1
      fi
      ;;
    timeout_green_mergeable)
      if [[ "$(cat "$review_calls")" != "1" ]]; then
        echo "expected one review attempt before fallback merge in timeout_green_mergeable" >&2
        return 1
      fi
      if [[ "$(cat "$merge_calls")" != "1" ]]; then
        echo "expected one merge attempt after fallback in timeout_green_mergeable" >&2
        return 1
      fi
      if ! grep -q 'class=review-timeout' "$home_dir/sgt/sgt.log"; then
        echo "expected timeout classification in structured unclear telemetry" >&2
        return 1
      fi
      ;;
    checks_missing_hold)
      if [[ "$(cat "$review_calls")" != "1" ]]; then
        echo "expected one review attempt before cap hold in checks_missing_hold" >&2
        return 1
      fi
      if [[ -s "$merge_calls" ]]; then
        if [[ "$(cat "$merge_calls")" != "0" ]]; then
          echo "expected no merge attempt when checks are missing" >&2
          return 1
        fi
      fi
      if ! grep -q 'REVIEW_UNCLEAR saturated — awaiting manual intervention (attempts=1/1 reason_code=checks-not-green)' "$home_dir/sgt/refinery-pass2.out"; then
        echo "expected clear terminal hold reason when checks are not green" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_REVIEW_UNCLEAR_CAP_HOLD pr=#123 issue=#77 attempts=1/1 .*reason_code=checks-not-green' "$home_dir/sgt/sgt.log"; then
        echo "expected structured cap-hold reason_code for checks_missing_hold" >&2
        return 1
      fi
      ;;
    explicit_error_gate_hold)
      if [[ "$(cat "$review_calls")" != "1" ]]; then
        echo "expected one review attempt before explicit error-gate hold" >&2
        return 1
      fi
      if [[ -s "$merge_calls" ]]; then
        if [[ "$(cat "$merge_calls")" != "0" ]]; then
          echo "expected no merge attempt for explicit error-gate class" >&2
          return 1
        fi
      fi
      if ! grep -q 'REVIEW_UNCLEAR saturated — awaiting manual intervention (attempts=1/1 reason_code=explicit-error-gate)' "$home_dir/sgt/refinery-pass2.out"; then
        echo "expected explicit error-gate hold reason when review contract conflicts" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_REVIEW_UNCLEAR_CAP_HOLD pr=#123 issue=#77 attempts=1/1 .*reason_code=explicit-error-gate' "$home_dir/sgt/sgt.log"; then
        echo "expected structured explicit error-gate cap-hold telemetry" >&2
        return 1
      fi
      ;;
    stale_head_resync)
      if [[ "$(cat "$review_calls")" != "1" ]]; then
        echo "expected one review attempt before stale-head resync" >&2
        return 1
      fi
      if [[ -s "$merge_calls" ]]; then
        if [[ "$(cat "$merge_calls")" != "0" ]]; then
          echo "expected no merge attempt when stale head is detected" >&2
          return 1
        fi
      fi
      if ! grep -q '^REVIEW_STATE=REVIEW_PENDING$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected stale-head case to resync queue to REVIEW_PENDING" >&2
        return 1
      fi
      if ! grep -Eq "^REVIEWED_HEAD_SHA=('')?$" "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected stale-head case to clear REVIEWED_HEAD_SHA" >&2
        return 1
      fi
      if ! grep -q '^REVIEW_RESYNC_REASON_CODE=stale-reviewed-head$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected stale-head resync reason marker" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_PREMERGE_SKIP pr=#123 reason_code=stale-reviewed-head' "$home_dir/sgt/sgt.log"; then
        echo "expected structured stale-head premerge skip telemetry" >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported mode: $mode" >&2
      return 1
      ;;
  esac
}

run_case empty_green_mergeable
run_case timeout_green_mergeable
run_case checks_missing_hold
run_case explicit_error_gate_hold
run_case stale_head_resync

echo "ALL TESTS PASSED"
