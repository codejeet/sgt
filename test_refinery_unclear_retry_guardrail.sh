#!/usr/bin/env bash
# test_refinery_unclear_retry_guardrail.sh — Regression checks for REVIEW_UNCLEAR retry backoff, saturation escalation, and restart replay.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

run_case() {
  local mode="$1"
  local tmp_root home_dir mock_bin
  local review_calls merge_calls openclaw_calls
  tmp_root="$(mktemp -d)"
  trap 'rm -rf "$tmp_root"' RETURN

  home_dir="$tmp_root/home"
  mock_bin="$tmp_root/mockbin"
  review_calls="$tmp_root/review-calls"
  merge_calls="$tmp_root/merge-calls"
  openclaw_calls="$tmp_root/openclaw-calls"
  mkdir -p "$home_dir/.local/bin" "$mock_bin"
  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"
  : > "$review_calls"
  : > "$merge_calls"
  : > "$openclaw_calls"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

MODE="${SGT_MOCK_MODE:?missing SGT_MOCK_MODE}"
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
    title) echo "Unclear retry issue" ;;
    body) echo "Issue body for unclear retry regression" ;;
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
    title) echo "Unclear retry regression PR" ;;
    body) echo "PR body" ;;
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
  echo "diff --git a/file.txt b/file.txt"
  echo "+change"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  inc_file "$MERGE_CALLS_FILE" >/dev/null
  if [[ "$MODE" == "success_reset" ]]; then
    echo "GraphQL: branch protection blocked merge" >&2
    exit 1
  fi
  echo "unexpected merge call for mode=$MODE" >&2
  exit 2
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "reopen" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "close" ]]; then
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
    success_reset)
      if [[ "$n" -eq 1 ]]; then
        echo "Need more information before final verdict."
      else
        echo "VERDICT: APPROVE"
      fi
      ;;
  cap_hit_dedupe)
    cat <<'OUT'
VERDICT: APPROVE
VERDICT: REJECT
OUT
    ;;
  restart_replay)
    echo "Analysis incomplete without definitive verdict."
    ;;
  *)
    echo "unsupported mode: $MODE" >&2
    exit 1
    ;;
esac
AIPROMPT
  chmod +x "$mock_bin/_ai_promptfile"

  cat > "$mock_bin/openclaw" <<'OPENCLAW'
#!/usr/bin/env bash
set -euo pipefail
CALLS_FILE="${SGT_MOCK_OPENCLAW_CALLS:?missing SGT_MOCK_OPENCLAW_CALLS}"
printf '%s\n' "$*" >> "$CALLS_FILE"
exit 0
OPENCLAW
  chmod +x "$mock_bin/openclaw"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_AI_BACKEND=claude \
    SGT_MOCK_MODE="$mode" \
    SGT_MOCK_REVIEW_CALLS="$review_calls" \
    SGT_MOCK_MERGE_CALLS="$merge_calls" \
    SGT_MOCK_OPENCLAW_CALLS="$openclaw_calls" \
    SGT_REFINERY_MERGE_MAX_ATTEMPTS=1 \
    SGT_REFINERY_REVIEW_UNCLEAR_BACKOFF_BASE_SECS=0 \
    SGT_REFINERY_REVIEW_UNCLEAR_JITTER_SECS=0 \
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
cat > "$SGT_ROOT/.sgt/notify.json" <<JSON
{"channel":"last","to":"rigger","reply_to":"sgt"}
JSON

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
REVIEW_STATE=REVIEW_PENDING
REVIEW_UPDATED_AT=$(date +%s)
REVIEW_UNCLEAR_SINCE=
REVIEW_UNCLEAR_RETRY_COUNT=0
REVIEW_UNCLEAR_NEXT_RETRY_AT=0
REVIEW_UNCLEAR_LAST_REASON=
REVIEW_UNCLEAR_ESCALATED=0
REVIEW_UNCLEAR_ESCALATED_AT=
REVIEWED_HEAD_SHA=
REVIEWED_AT=
QUEUED=$(date -Iseconds)
MQ

case "$SGT_MOCK_MODE" in
  success_reset)
    run_refinery_pass pass1
    force_retry_now
    run_refinery_pass pass2
    ;;
  cap_hit_dedupe)
    export SGT_REFINERY_REVIEW_UNCLEAR_MAX_RETRIES=2
    run_refinery_pass pass1
    force_retry_now
    run_refinery_pass pass2
    force_retry_now
    run_refinery_pass pass3
    ;;
  restart_replay)
    export SGT_REFINERY_REVIEW_UNCLEAR_MAX_RETRIES=5
    export SGT_REFINERY_REVIEW_UNCLEAR_BACKOFF_BASE_SECS=120
    run_refinery_pass pass1
    run_refinery_pass pass2
    ;;
  *)
    echo "unsupported mode: $SGT_MOCK_MODE" >&2
    exit 1
    ;;
esac
'

  case "$mode" in
    success_reset)
      if [[ "$(cat "$review_calls")" != "2" ]]; then
        echo "expected two review passes for success_reset" >&2
        return 1
      fi
      if [[ "$(cat "$merge_calls")" != "1" ]]; then
        echo "expected one merge attempt for success_reset" >&2
        return 1
      fi
      if [[ ! -f "$home_dir/sgt/.sgt/merge-queue/test-pr123" ]]; then
        echo "expected queue entry to remain after forced merge failure in success_reset" >&2
        return 1
      fi
      if ! grep -q '^REVIEW_STATE=REVIEW_APPROVED$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected REVIEW_APPROVED after second pass in success_reset" >&2
        return 1
      fi
      if ! grep -q '^REVIEW_UNCLEAR_RETRY_COUNT=0$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected unclear retry count reset after successful review" >&2
        return 1
      fi
      if ! grep -q '^REVIEW_UNCLEAR_ESCALATED=0$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected unclear escalation marker reset after successful review" >&2
        return 1
      fi
      ;;
    cap_hit_dedupe)
      if [[ "$(cat "$review_calls")" != "2" ]]; then
        echo "expected review attempts to stop at retry cap with dedupe hold" >&2
        return 1
      fi
      if ! grep -q '^REVIEW_UNCLEAR_RETRY_COUNT=2$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected retry count to persist at cap" >&2
        return 1
      fi
      if ! grep -q '^REVIEW_UNCLEAR_ESCALATED=1$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected escalation marker to persist after cap hit" >&2
        return 1
      fi
      if [[ "$(wc -l < "$openclaw_calls")" != "1" ]]; then
        echo "expected exactly one openclaw escalation notification at cap" >&2
        return 1
      fi
      if ! grep -q 'pr=#123 issue=#77' "$openclaw_calls"; then
        echo "expected escalation payload to include PR and issue context" >&2
        return 1
      fi
      if ! grep -q 'last_reason=' "$openclaw_calls"; then
        echo "expected escalation payload to include last failure reason" >&2
        return 1
      fi
      if ! grep -q 'next_action=' "$openclaw_calls"; then
        echo "expected escalation payload to include next action hint" >&2
        return 1
      fi
      if [[ "$(grep -c 'REFINERY_REVIEW_UNCLEAR_ESCALATED pr=#123 issue=#77' "$home_dir/sgt/sgt.log")" != "1" ]]; then
        echo "expected exactly one structured unclear escalation event across restart replay" >&2
        return 1
      fi
      if ! grep -q 'REVIEW_UNCLEAR saturated — awaiting manual intervention' "$home_dir/sgt/refinery-pass3.out"; then
        echo "expected replay pass to hold at unclear cap without re-escalating" >&2
        return 1
      fi
      ;;
    restart_replay)
      if [[ "$(cat "$review_calls")" != "1" ]]; then
        echo "expected restart replay pass to honor persisted backoff without a new review" >&2
        return 1
      fi
      if ! grep -q '^REVIEW_UNCLEAR_RETRY_COUNT=1$' "$home_dir/sgt/.sgt/merge-queue/test-pr123"; then
        echo "expected retry count to persist after first unclear attempt" >&2
        return 1
      fi
      if ! grep -q 'REVIEW_UNCLEAR backoff active — retry in ' "$home_dir/sgt/refinery-pass2.out"; then
        echo "expected restart replay pass to report active unclear backoff window" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_REVIEW_UNCLEAR_BACKOFF pr=#123 issue=#77 attempt=1' "$home_dir/sgt/sgt.log"; then
        echo "expected structured unclear backoff event during restart replay hold" >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported mode: $mode" >&2
      return 1
      ;;
  esac
}

run_case success_reset
run_case cap_hit_dedupe
run_case restart_replay

echo "ALL TESTS PASSED"
