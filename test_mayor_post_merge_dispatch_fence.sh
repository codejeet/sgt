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

SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_CONFIG"

reason='merged:pr#123:#77:test-rig|repo=https://github.com/acme/demo|title=Merged fix|pr_url=https://github.com/acme/demo/pull/123|issue_url=https://github.com/acme/demo/issues/77|merged_head=abc123'

if [[ "$PASS_NAME" == "first" ]]; then
  if ! _mayor_dispatch_trigger_claim "$reason"; then
    echo "expected first merged-trigger claim to succeed" >&2
    exit 1
  fi
  key="${_MAYOR_DISPATCH_TRIGGER_KEY:-}"
  if [[ "$key" != "acme/demo|pr=123|merged_head=abc123" ]]; then
    echo "unexpected merged-trigger key: $key" >&2
    exit 1
  fi
fi

duplicate_attempts=1
if [[ "$PASS_NAME" == "first" ]]; then
  duplicate_attempts=3
fi
for ((attempt=1; attempt<=duplicate_attempts; attempt++)); do
  set +e
  _mayor_dispatch_trigger_claim "$reason"
  rc=$?
  set -e
  if [[ "$rc" -ne 1 ]]; then
    echo "expected duplicate merged-trigger claim rc=1 on attempt $attempt, got rc=$rc" >&2
    exit 1
  fi

  dup_key="${_MAYOR_DISPATCH_TRIGGER_KEY:-unknown}"
  reason_code="duplicate-dispatch-trigger-key"
  skip_reason="duplicate merged dispatch trigger key (repo+pr+merged_head) already claimed"
  trigger_event_key="$(_wake_trigger_key "$reason")"
  dup_repo="$(_wake_field "$reason" "repo")"
  dup_merged_head="$(_wake_field "$reason" "merged_head")"
  dup_pr=""
  dup_issue=""
  dup_rig=""
  if [[ "$reason" =~ ^merged:pr#([0-9]+):#([0-9]+):([^|]+) ]]; then
    dup_pr="${BASH_REMATCH[1]}"
    dup_issue="${BASH_REMATCH[2]}"
    dup_rig="${BASH_REMATCH[3]}"
  fi
  log_event "MAYOR_DISPATCH_SKIPPED_DUPLICATE reason_code=$reason_code skip_reason=\"$(_escape_quotes "$skip_reason")\" trigger_event_key=\"$(_escape_quotes "$trigger_event_key")\" rig=$dup_rig repo=\"$(_escape_quotes "$dup_repo")\" pr=#${dup_pr:-unknown} issue=#${dup_issue:-unknown} merged_head=\"$(_escape_quotes "$dup_merged_head")\" key=\"$(_escape_quotes "$dup_key")\" wake=\"$(_escape_quotes "$reason")\""
done
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

if ! grep -q 'merged_head=$(_escape_wake_value "$merge_expected_head_sha")' "$SGT_SCRIPT"; then
  echo "expected merged wake payload to include merged_head metadata for dispatch fence keying" >&2
  exit 1
fi

if ! grep -q 'MAYOR_DISPATCH_SKIPPED_DUPLICATE reason_code=' "$SGT_SCRIPT"; then
  echo "expected mayor duplicate merged-trigger branch to emit structured reason code logging" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
