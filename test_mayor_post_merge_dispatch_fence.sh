#!/usr/bin/env bash
# test_mayor_post_merge_dispatch_fence.sh — Regression checks for durable mayor post-merge dispatch dedupe fence.

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

run_claim_pass() {
  local pass_name="$1"
  bash -s "$SGT_SCRIPT" "$TMP_ROOT" "$pass_name" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
TMP_ROOT="$2"
PASS_NAME="$3"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _repo_owner_repo)"
eval "$(extract_fn _wake_field)"
eval "$(extract_fn _wake_trigger_key)"
eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn log_event)"
eval "$(extract_fn _mayor_dispatch_trigger_key)"
eval "$(extract_fn _mayor_dispatch_trigger_key_id)"
eval "$(extract_fn _mayor_dispatch_trigger_claim)"
eval "$(extract_fn _wake_requires_dispatch_decision)"
eval "$(extract_fn _mayor_wake_summary)"

SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_CONFIG"
NOTIFY_LOG="$TMP_ROOT/notify.log"
DECISION_LOG="$TMP_ROOT/decision.log"

_mayor_notify_rigger() {
  local message="${1:-}"
  printf '%s\n' "$message" >> "$NOTIFY_LOG"
}

_mayor_record_decision() {
  local entry="${1:-}"
  local context="${2:-cycle}"
  printf '%s|%s\n' "$context" "$entry" >> "$DECISION_LOG"
}

reason='merged:pr#123:#77:test-rig|repo=https://github.com/acme/demo|title=Merged fix|pr_url=https://github.com/acme/demo/pull/123|issue_url=https://github.com/acme/demo/issues/77|merged_head=abc123'

process_wake_reason() {
  local event_reason="$1"
  local suppress_wake_summary="false"
  local claim_rc

  if _wake_requires_dispatch_decision "$event_reason"; then
    if [[ "$event_reason" == merged:* ]]; then
      if _mayor_dispatch_trigger_claim "$event_reason"; then
        :
      else
        claim_rc=$?
        if [[ "$claim_rc" -eq 1 ]]; then
          local duplicate_key duplicate_reason_code duplicate_reason duplicate_event_key duplicate_repo duplicate_pr duplicate_issue duplicate_rig duplicate_merged_head
          duplicate_key="${_MAYOR_DISPATCH_TRIGGER_KEY:-unknown}"
          duplicate_reason_code="duplicate-dispatch-trigger-key"
          duplicate_reason="duplicate merged dispatch trigger key (repo+pr+merged_head) already claimed"
          duplicate_event_key="$(_wake_trigger_key "$event_reason")"
          duplicate_repo="$(_wake_field "$event_reason" "repo")"
          duplicate_merged_head="$(_wake_field "$event_reason" "merged_head")"
          duplicate_pr=""
          duplicate_issue=""
          duplicate_rig=""
          if [[ "$event_reason" =~ ^merged:pr#([0-9]+):#([0-9]+):([^|]+) ]]; then
            duplicate_pr="${BASH_REMATCH[1]}"
            duplicate_issue="${BASH_REMATCH[2]}"
            duplicate_rig="${BASH_REMATCH[3]}"
          fi
          log_event "MAYOR_DISPATCH_SKIPPED_DUPLICATE reason_code=$duplicate_reason_code skip_reason=\"$(_escape_quotes "$duplicate_reason")\" trigger_event_key=\"$(_escape_quotes "$duplicate_event_key")\" rig=$duplicate_rig repo=\"$(_escape_quotes "$duplicate_repo")\" pr=#${duplicate_pr:-unknown} issue=#${duplicate_issue:-unknown} merged_head=\"$(_escape_quotes "$duplicate_merged_head")\" key=\"$(_escape_quotes "$duplicate_key")\" wake=\"$(_escape_quotes "$event_reason")\""
          _mayor_record_decision "MAYOR WAKE SKIP (duplicate-merged-trigger) reason_code=$duplicate_reason_code trigger_key=$duplicate_key trigger_event_key=$duplicate_event_key wake=$event_reason" "dispatch-trigger-duplicate" "$SGT_ROOT" || true
          suppress_wake_summary="true"
        fi
      fi
    fi
  fi

  wake_summary="$(_mayor_wake_summary "$event_reason")"
  if [[ -n "$wake_summary" && "$suppress_wake_summary" != "true" ]]; then
    _mayor_notify_rigger "$wake_summary"
  fi
}

attempts=1
if [[ "$PASS_NAME" == "first" ]]; then
  attempts=4
fi
for ((attempt=1; attempt<=attempts; attempt++)); do
  process_wake_reason "$reason"
done

key="${_MAYOR_DISPATCH_TRIGGER_KEY:-}"
if [[ "$key" != "acme/demo|pr=123|merged_head=abc123" ]]; then
  echo "unexpected merged-trigger key: $key" >&2
  exit 1
fi
BASH
}

run_claim_pass first
run_claim_pass restart

KEY_DIR="$TMP_ROOT/root/.sgt/mayor-dispatch-triggers"
if [[ ! -d "$KEY_DIR" ]]; then
  echo "expected durable mayor dispatch trigger directory to exist" >&2
  exit 1
fi
if [[ "$(find "$KEY_DIR" -type f | wc -l | tr -d ' ')" != "1" ]]; then
  echo "expected exactly one durable dispatch-trigger key file" >&2
  exit 1
fi

LOG_FILE="$TMP_ROOT/root/sgt.log"
if [[ "$(grep -c 'MAYOR_DISPATCH_SKIPPED_DUPLICATE reason_code=duplicate-dispatch-trigger-key' "$LOG_FILE" || true)" -lt 4 ]]; then
  echo "expected rapid duplicate merged-trigger skips + restart replay to log structured MAYOR_DISPATCH_SKIPPED_DUPLICATE events" >&2
  exit 1
fi

if ! grep -Fq 'MAYOR_DISPATCH_SKIPPED_DUPLICATE reason_code=duplicate-dispatch-trigger-key' "$LOG_FILE" || \
   ! grep -Fq 'trigger_event_key="merged:pr#123:#77:test-rig"' "$LOG_FILE" || \
   ! grep -Fq 'repo="https://github.com/acme/demo"' "$LOG_FILE" || \
   ! grep -Fq 'pr=#123 issue=#77 merged_head="abc123"' "$LOG_FILE" || \
   ! grep -Fq 'key="acme/demo|pr=123|merged_head=abc123"' "$LOG_FILE"; then
  echo "expected duplicate merged-trigger skip logs to include structured trigger context fields" >&2
  exit 1
fi

NOTIFY_LOG="$TMP_ROOT/notify.log"
if [[ "$(wc -l < "$NOTIFY_LOG" | tr -d ' ')" != "1" ]]; then
  echo "expected duplicate merged-trigger replay (same-process + restart) to suppress duplicate mayor wake notifications" >&2
  exit 1
fi

DECISION_LOG="$TMP_ROOT/decision.log"
if [[ "$(grep -c '^dispatch-trigger-duplicate|MAYOR WAKE SKIP (duplicate-merged-trigger) reason_code=duplicate-dispatch-trigger-key' "$DECISION_LOG" || true)" -lt 4 ]]; then
  echo "expected duplicate merged-trigger replay to emit explicit duplicate-suppressed decision telemetry" >&2
  exit 1
fi
if ! grep -Fq 'trigger_key=acme/demo|pr=123|merged_head=abc123' "$DECISION_LOG"; then
  echo "expected duplicate-suppressed decision telemetry to include durable trigger key" >&2
  exit 1
fi

if ! grep -q 'merged_head=$(_escape_wake_value "$merge_expected_head_sha")' "$SGT_SCRIPT"; then
  echo "expected merged wake payload to include merged_head metadata for dispatch fence keying" >&2
  exit 1
fi

if ! grep -q 'MAYOR_DISPATCH_SKIPPED_DUPLICATE reason_code=' "$SGT_SCRIPT"; then
  echo "expected mayor duplicate merged-trigger branch to emit structured reason code logging" >&2
  exit 1
fi

if ! grep -q 'MAYOR WAKE SKIP (duplicate-merged-trigger) reason_code=' "$SGT_SCRIPT"; then
  echo "expected mayor duplicate merged-trigger branch to emit structured decision-log telemetry" >&2
  exit 1
fi

if ! grep -q 'suppress_wake_summary' "$SGT_SCRIPT" || \
   ! grep -q '_mayor_notify_rigger "\$wake_summary"' "$SGT_SCRIPT"; then
  echo "expected mayor wake summary notifications to be gated by duplicate merged-trigger suppression" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
