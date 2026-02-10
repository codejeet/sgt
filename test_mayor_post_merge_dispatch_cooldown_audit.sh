#!/usr/bin/env bash
# test_mayor_post_merge_dispatch_cooldown_audit.sh — Regression checks for mayor dispatch-cooldown suppression telemetry + durable audit trail.

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

bash -s "$SGT_SCRIPT" "$TMP_ROOT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
TMP_ROOT="$2"

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
eval "$(extract_fn _wake_trigger_should_suppress)"
eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn log_event)"
eval "$(extract_fn _mayor_dispatch_trigger_key)"
eval "$(extract_fn _mayor_dispatch_trigger_key_id)"
eval "$(extract_fn _mayor_dispatch_trigger_claim)"
eval "$(extract_fn _wake_requires_dispatch_decision)"

SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_CONFIG"
DECISION_LOG="$TMP_ROOT/decision.log"
NOTIFY_LOG="$TMP_ROOT/notify.log"

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
wake_dedupe_ttl=15
declare -A wake_seen_at=()
dispatch_decisions=0

process_wake_reason() {
  local event_reason="${1:-}" now_ts="${2:-0}"
  local event_key last_seen age skip_reason ttl_remaining prior_decision_ts claim_rc

  event_key="$(_wake_trigger_key "$event_reason")"
  if [[ -n "$event_key" ]]; then
    last_seen="${wake_seen_at[$event_key]:-}"
  else
    last_seen=""
  fi

  if [[ -n "$event_key" && "$wake_dedupe_ttl" -gt 0 ]] && _wake_trigger_should_suppress "$last_seen" "$now_ts" "$wake_dedupe_ttl"; then
    age=$((now_ts - last_seen))
    ttl_remaining=$((wake_dedupe_ttl - age))
    if [[ "$ttl_remaining" -lt 0 ]]; then
      ttl_remaining=0
    fi
    prior_decision_ts="$last_seen"
    skip_reason="dispatch cooldown active (reason=dispatch_cooldown trigger_key=$event_key age=${age}s ttl=${wake_dedupe_ttl}s ttl_remaining=${ttl_remaining}s prior_decision_ts=${prior_decision_ts})"
    log_event "MAYOR_DISPATCH_COOLDOWN_SUPPRESSED reason=dispatch_cooldown trigger_key=\"$(_escape_quotes "$event_key")\" ttl_remaining=${ttl_remaining}s prior_decision_ts=${prior_decision_ts} wake=\"$(_escape_quotes "$event_reason")\""
    _mayor_notify_rigger "mayor skip: $skip_reason"
    _mayor_record_decision "MAYOR WAKE SKIP reason=dispatch_cooldown trigger_key=$event_key ttl_remaining=${ttl_remaining}s prior_decision_ts=${prior_decision_ts} wake=$event_reason" "dispatch-cooldown-skip" "$SGT_ROOT" || true
    return 0
  fi

  if [[ -n "$event_key" ]]; then
    wake_seen_at["$event_key"]="$now_ts"
  fi

  if _wake_requires_dispatch_decision "$event_reason"; then
    if [[ "$event_reason" == merged:* ]]; then
      if _mayor_dispatch_trigger_claim "$event_reason"; then
        dispatch_decisions=$((dispatch_decisions + 1))
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
        fi
      fi
    fi
  fi
}

# Replayed merged wake events:
# - 100: first event dispatches
# - 105: suppressed by wake dispatch cooldown TTL
# - 116: outside TTL, reaches durable merged-trigger duplicate fence
# - 117: suppressed by wake dispatch cooldown TTL again
process_wake_reason "$reason" 100
process_wake_reason "$reason" 105
process_wake_reason "$reason" 116
process_wake_reason "$reason" 117

if [[ "$dispatch_decisions" -ne 1 ]]; then
  echo "expected exactly one dispatch decision under repeated merged events, got $dispatch_decisions" >&2
  exit 1
fi
BASH

LOG_FILE="$TMP_ROOT/root/sgt.log"
DECISION_LOG="$TMP_ROOT/decision.log"

if [[ "$(grep -c 'MAYOR_DISPATCH_COOLDOWN_SUPPRESSED reason=dispatch_cooldown' "$LOG_FILE" || true)" -ne 2 ]]; then
  echo "expected exactly two structured dispatch-cooldown suppressions in activity log" >&2
  exit 1
fi

if ! grep -Fq 'trigger_key="merged:pr#123:#77:test-rig"' "$LOG_FILE" || \
   ! grep -Fq 'ttl_remaining=10s' "$LOG_FILE" || \
   ! grep -Fq 'prior_decision_ts=100' "$LOG_FILE"; then
  echo "expected dispatch-cooldown suppression telemetry to include trigger_key, ttl_remaining, and prior_decision_ts" >&2
  exit 1
fi

if [[ "$(grep -c '^dispatch-cooldown-skip|MAYOR WAKE SKIP reason=dispatch_cooldown' "$DECISION_LOG" || true)" -ne 2 ]]; then
  echo "expected exactly two durable dispatch-cooldown decision-log entries" >&2
  exit 1
fi

if ! grep -Fq 'reason=dispatch_cooldown trigger_key=merged:pr#123:#77:test-rig ttl_remaining=10s prior_decision_ts=100' "$DECISION_LOG"; then
  echo "expected durable decision-log entry to include dispatch cooldown context fields" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
