#!/usr/bin/env bash
# test_refinery_post_merge_verification_receipt_fence.sh — Regression coverage for refinery post-merge verification receipt fence.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

run_case() {
  local mode="$1"
  local tmp_root home_dir mock_bin merge_calls merge_commit_calls
  tmp_root="$(mktemp -d)"
  trap 'rm -rf "$tmp_root"' RETURN

  home_dir="$tmp_root/home"
  mock_bin="$tmp_root/mockbin"
  merge_calls="$tmp_root/merge-calls"
  merge_commit_calls="$tmp_root/merge-commit-calls"
  mkdir -p "$home_dir/.local/bin" "$mock_bin"
  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"
  printf '0\n' > "$merge_calls"
  printf '0\n' > "$merge_commit_calls"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

MODE="${SGT_MOCK_MODE:?missing SGT_MOCK_MODE}"
MERGE_CALLS_FILE="${SGT_MOCK_MERGE_CALLS:?missing SGT_MOCK_MERGE_CALLS}"
MERGE_COMMIT_CALLS_FILE="${SGT_MOCK_MERGE_COMMIT_CALLS:?missing SGT_MOCK_MERGE_COMMIT_CALLS}"

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
    title) echo "Post merge verification issue" ;;
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
    title)
      echo "Post merge verification PR"
      ;;
    state)
      echo "OPEN"
      ;;
    mergeable)
      echo "MERGEABLE"
      ;;
    state,headRefOid)
      echo "OPEN|live111"
      ;;
    state,mergeCommit)
      if [[ "$MODE" == "stale_api_lag" ]]; then
        call_n="$(inc_file "$MERGE_COMMIT_CALLS_FILE")"
        if [[ "$call_n" -eq 1 ]]; then
          echo "OPEN|"
        else
          echo "MERGED|mergeabc123"
        fi
      else
        echo "MERGED|mergeabc123"
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
  inc_file "$MERGE_CALLS_FILE" >/dev/null
  echo "merged"
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  if [[ "${2:-}" == "repos/acme/demo/branches/sgt%2Ftest-pr123" ]]; then
    echo "Not Found" >&2
    exit 1
  fi
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
    SGT_MOCK_MERGE_COMMIT_CALLS="$merge_commit_calls" \
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

if [[ "$SGT_MOCK_MODE" == "partial_receipt_replay" ]]; then
  key="acme/demo|pr=123|head=live111"
  key_id="$(printf "%s" "$key" | sha256sum | awk "{print \$1}")"
  mkdir -p "$SGT_ROOT/.sgt/refinery-merge-attempts" "$SGT_ROOT/.sgt/refinery-merge-receipts"
  cat > "$SGT_ROOT/.sgt/refinery-merge-attempts/$key_id" <<AT
KEY=$key
REPO=https://github.com/acme/demo
PR=123
HEAD_SHA=live111
QUEUE=test-pr123
CLAIMED_AT=$(date -Iseconds)
AT
  cat > "$SGT_ROOT/.sgt/refinery-merge-receipts/$key_id.state" <<REC
KEY=$key
REPO=acme/demo
PR=123
ISSUE=77
EXPECTED_STATE=pr_state=MERGED;issue_state=OPEN;branch_deleted=true
OBSERVED_STATE=pr_state=MERGED;issue_state=OPEN;branch_deleted=true
MERGED_SHA=mergeabc123
BRANCH_DELETED=true
VERIFIED_AT=$(date -Iseconds)
REC
fi

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
if [[ "$SGT_MOCK_MODE" == "stale_api_lag" ]]; then
  run_pass "$SGT_ROOT/refinery-pass2.out"
fi
'

  local receipt_file
  receipt_file="$(ls "$home_dir/sgt/.sgt/refinery-merge-receipts"/*.state 2>/dev/null | head -1 || true)"
  if [[ -z "$receipt_file" ]]; then
    echo "expected merge receipt file" >&2
    return 1
  fi

  case "$mode" in
    normal_merge)
      if [[ "$(cat "$merge_calls")" != "1" ]]; then
        echo "expected one merge call for normal_merge" >&2
        return 1
      fi
      if [[ -f "$home_dir/sgt/.sgt/merge-queue/test-pr123" ]]; then
        echo "expected queue removal on verified success" >&2
        return 1
      fi
      if ! grep -q '^OUTCOME=success$' "$receipt_file"; then
        echo "expected success outcome in receipt" >&2
        return 1
      fi
      ;;
    stale_api_lag)
      if [[ "$(cat "$merge_calls")" != "1" ]]; then
        echo "expected merge command to run once for stale_api_lag" >&2
        return 1
      fi
      if ! grep -q 'post-merge verification mismatch' "$home_dir/sgt/refinery-pass1.out"; then
        echo "expected mismatch in first pass for stale_api_lag" >&2
        return 1
      fi
      if grep -q 'merged successfully' "$home_dir/sgt/refinery-pass1.out"; then
        echo "did not expect merged-complete signal in stale first pass" >&2
        return 1
      fi
      if ! grep -q 'replaying post-merge verification receipt fence' "$home_dir/sgt/refinery-pass2.out"; then
        echo "expected replay verification fence status in second pass" >&2
        return 1
      fi
      if ! grep -q 'merged successfully' "$home_dir/sgt/refinery-pass2.out"; then
        echo "expected merged success after lag clears" >&2
        return 1
      fi
      if [[ -f "$home_dir/sgt/.sgt/merge-queue/test-pr123" ]]; then
        echo "expected queue removal after replay verification success" >&2
        return 1
      fi
      if ! grep -q '^OUTCOME=success$' "$receipt_file"; then
        echo "expected final success outcome in stale_api_lag receipt" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_MERGE_RECEIPT non-success reason=post-merge-live-mismatch' "$home_dir/sgt/sgt.log"; then
        echo "expected non-success receipt log for stale_api_lag" >&2
        return 1
      fi
      ;;
    partial_receipt_replay)
      if [[ "$(cat "$merge_calls")" != "0" ]]; then
        echo "expected no merge calls when recovering partial receipt replay" >&2
        return 1
      fi
      if ! grep -q 'REFINERY_MERGE_RECEIPT non-success reason=partial-receipt-write' "$home_dir/sgt/sgt.log"; then
        echo "expected partial receipt recovery log event" >&2
        return 1
      fi
      if [[ -f "$home_dir/sgt/.sgt/merge-queue/test-pr123" ]]; then
        echo "expected queue removal after partial receipt recovery" >&2
        return 1
      fi
      if ! grep -q '^OUTCOME=success$' "$receipt_file"; then
        echo "expected recovered success outcome in receipt" >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported mode: $mode" >&2
      return 1
      ;;
  esac

  for required in REPO PR ISSUE EXPECTED_STATE OBSERVED_STATE MERGED_SHA BRANCH_DELETED VERIFIED_AT OUTCOME; do
    if ! grep -q "^${required}=" "$receipt_file"; then
      echo "expected receipt field $required in $mode" >&2
      return 1
    fi
  done
}

run_case normal_merge
run_case stale_api_lag
run_case partial_receipt_replay

echo "ALL TESTS PASSED"
