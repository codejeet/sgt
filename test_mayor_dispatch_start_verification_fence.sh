#!/usr/bin/env bash
# test_mayor_dispatch_start_verification_fence.sh — Regression checks for durable mayor dispatch-start verifier + single-retry fence.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

run_case() {
  local case_name="$1"
  bash -s "$SGT_SCRIPT" "$TMP_ROOT" "$case_name" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
TMP_ROOT="$2"
CASE_NAME="$3"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _escape_wake_value)"
eval "$(extract_fn _repo_owner_repo)"
eval "$(extract_fn _mayor_dispatch_trigger_key_id)"
eval "$(extract_fn _merge_queue_set_field)"
eval "$(extract_fn _resling_find_existing_issue_polecat)"
eval "$(extract_fn _mayor_dispatch_attempts_dir)"
eval "$(extract_fn _mayor_dispatch_verify_timeout_secs)"
eval "$(extract_fn _mayor_dispatch_attempt_key)"
eval "$(extract_fn _mayor_dispatch_attempt_claim)"
eval "$(extract_fn _mayor_dispatch_attempt_mark)"
eval "$(extract_fn _mayor_dispatch_attempt_active_signal)"
eval "$(extract_fn _mayor_dispatch_attempt_retry_once)"
eval "$(extract_fn _mayor_dispatch_verify_replay)"
eval "$(extract_fn log_event)"

_mayor_record_decision() { :; }
_ai_backend_default() { echo "claude"; }

SGT_ROOT="$TMP_ROOT/$CASE_NAME/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_POLECATS="$SGT_CONFIG/polecats"
SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_CONFIG" "$SGT_POLECATS"

_RESLING_LAST_POLECAT=""
_RESLING_RETRY_CALLS=0
_resling_existing_issue() {
  local rig="$1" issue="$2" task="$3" repo="$4"
  _RESLING_RETRY_CALLS=$((_RESLING_RETRY_CALLS + 1))
  case "$CASE_NAME" in
    timeout-single-retry)
      return 1
      ;;
    *)
      _RESLING_LAST_POLECAT="${rig}-retry-${issue}"
      cat > "$SGT_POLECATS/${_RESLING_LAST_POLECAT}" <<PSTATE
RIG=$rig
REPO=$repo
ISSUE=$issue
PSTATE
      return 0
      ;;
  esac
}

gh() {
  if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
    echo "Retry generated title"
    return 0
  fi
  return 1
}

tmux() {
  if [[ "${1:-}" == "has-session" ]]; then
    return 1
  fi
  return 1
}

repo="https://github.com/acme/demo"
trigger="merged:pr#123:#77:test-rig"

case "$CASE_NAME" in
  success)
    SGT_MAYOR_DISPATCH_VERIFY_TIMEOUT_SECS=120
    _mayor_dispatch_attempt_claim "$repo" "77" "$trigger" "$trigger" "test-rig" "https://github.com/acme/demo/issues/77" "test-rig-abc" "sgt-test-rig-abc"
    cat > "$SGT_POLECATS/test-rig-abc" <<PSTATE
RIG=test-rig
REPO=$repo
ISSUE=77
PSTATE
    _mayor_dispatch_verify_replay
    attempt_file="${_MAYOR_DISPATCH_ATTEMPT_FILE:-}"
    if ! grep -q '^VERIFY_STATUS=VERIFIED$' "$attempt_file"; then
      echo "expected success case to mark attempt VERIFIED" >&2
      exit 1
    fi
    if ! grep -q '^VERIFY_REASON=active-polecat:test-rig-abc$' "$attempt_file"; then
      echo "expected success case reason to report active polecat" >&2
      exit 1
    fi
    ;;

  timeout-single-retry)
    SGT_MAYOR_DISPATCH_VERIFY_TIMEOUT_SECS=0
    _mayor_dispatch_attempt_claim "$repo" "78" "$trigger" "$trigger" "test-rig" "https://github.com/acme/demo/issues/78" "test-rig-def" "sgt-test-rig-def"
    _mayor_dispatch_verify_replay
    attempt_file="${_MAYOR_DISPATCH_ATTEMPT_FILE:-}"
    if [[ "$_RESLING_RETRY_CALLS" != "1" ]]; then
      echo "expected timeout case to perform exactly one retry dispatch attempt" >&2
      exit 1
    fi
    if ! grep -q '^VERIFY_STATUS=FAILED_TIMEOUT$' "$attempt_file"; then
      echo "expected timeout case to end in FAILED_TIMEOUT when retry dispatch fails" >&2
      exit 1
    fi
    if ! grep -q '^VERIFY_REASON=retry-dispatch-failed$' "$attempt_file"; then
      echo "expected timeout case to include explicit retry-dispatch-failed reason" >&2
      exit 1
    fi
    _mayor_dispatch_verify_replay
    if [[ "$_RESLING_RETRY_CALLS" != "1" ]]; then
      echo "expected timeout case to remain deduped at a single retry across replays" >&2
      exit 1
    fi
    ;;

  restart-replay)
    SGT_MAYOR_DISPATCH_VERIFY_TIMEOUT_SECS=0
    _mayor_dispatch_attempt_claim "$repo" "79" "$trigger" "$trigger" "test-rig" "https://github.com/acme/demo/issues/79" "test-rig-ghi" "sgt-test-rig-ghi"
    attempt_file="${_MAYOR_DISPATCH_ATTEMPT_FILE:-}"
    _merge_queue_set_field "$attempt_file" "RETRY_COUNT" "1"
    _merge_queue_set_field "$attempt_file" "RETRY_STATUS" "dispatched"
    _merge_queue_set_field "$attempt_file" "VERIFY_STATUS" "RETRY_PENDING"
    _merge_queue_set_field "$attempt_file" "VERIFY_DEADLINE_TS" "0"
    _mayor_dispatch_verify_replay
    if [[ "$_RESLING_RETRY_CALLS" != "0" ]]; then
      echo "expected restart replay case to suppress second retry attempt when retry budget already consumed" >&2
      exit 1
    fi
    if ! grep -q '^VERIFY_STATUS=FAILED_TIMEOUT$' "$attempt_file"; then
      echo "expected restart replay case to fail terminally after retry budget is exhausted" >&2
      exit 1
    fi
    if ! grep -q '^VERIFY_REASON=retry-budget-exhausted$' "$attempt_file"; then
      echo "expected restart replay case to report retry-budget-exhausted reason" >&2
      exit 1
    fi
    ;;

  duplicate-trigger)
    SGT_MAYOR_DISPATCH_VERIFY_TIMEOUT_SECS=120
    if ! _mayor_dispatch_attempt_claim "$repo" "80" "$trigger" "$trigger" "test-rig" "https://github.com/acme/demo/issues/80" "test-rig-jkl" "sgt-test-rig-jkl"; then
      echo "expected first duplicate-trigger claim to succeed" >&2
      exit 1
    fi
    if _mayor_dispatch_attempt_claim "$repo" "80" "$trigger" "$trigger" "test-rig" "https://github.com/acme/demo/issues/80" "test-rig-jkl" "sgt-test-rig-jkl"; then
      echo "expected duplicate-trigger claim to be suppressed" >&2
      exit 1
    fi
    if [[ "$(find "$SGT_CONFIG/mayor-dispatch-attempts" -type f | wc -l | tr -d ' ')" != "1" ]]; then
      echo "expected exactly one attempt record for duplicate issue+trigger claims" >&2
      exit 1
    fi
    ;;

  *)
    echo "unknown case $CASE_NAME" >&2
    exit 1
    ;;
esac
BASH
}

run_case success
run_case timeout-single-retry
run_case restart-replay
run_case duplicate-trigger

echo "ALL TESTS PASSED"
