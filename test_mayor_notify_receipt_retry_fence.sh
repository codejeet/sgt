#!/usr/bin/env bash
# test_mayor_notify_receipt_retry_fence.sh — Regression checks for mayor notify delivery receipts + single-retry fence.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

setup_case_env() {
  local case_name="$1"
  local home_dir="$TMP_ROOT/$case_name/home"
  local mock_bin="$TMP_ROOT/$case_name/mockbin"
  local state_dir="$TMP_ROOT/$case_name/state"
  mkdir -p "$home_dir/.local/bin" "$home_dir/sgt/.sgt" "$mock_bin" "$state_dir"

  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"

  cat > "$home_dir/sgt/.sgt/notify.json" <<'JSON'
{
  "channel": "rigger",
  "to": "ops",
  "reply_to": "thread-1"
}
JSON

  cat > "$mock_bin/openclaw" <<'OPENCLAW'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${SGT_MOCK_NOTIFY_STATE:?missing SGT_MOCK_NOTIFY_STATE}"
CASE_NAME="${SGT_MOCK_NOTIFY_CASE:-success}"
COUNT_FILE="$STATE_DIR/openclaw.count"
count=0
if [[ -f "$COUNT_FILE" ]]; then
  count="$(cat "$COUNT_FILE")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$COUNT_FILE"
printf '%s\n' "$*" >> "$STATE_DIR/openclaw.calls"

case "$CASE_NAME" in
  success)
    echo "ack=delivered message_id=success-$count"
    exit 0
    ;;
  ack_copy)
    echo "Copy."
    exit 0
    ;;
  ack_ack)
    echo "ACK!"
    exit 0
    ;;
  ack_received)
    echo "received,"
    exit 0
    ;;
  ack_roger)
    echo "rOgEr?"
    exit 0
    ;;
  non_ack_reply)
    echo "queued for routing"
    exit 0
    ;;
  transient_then_success)
    if [[ "$count" -eq 1 ]]; then
      echo "timeout waiting for transport ack" >&2
      exit 1
    fi
    echo "ack=delivered message_id=retry-$count"
    exit 0
    ;;
  hard_failure)
    echo "fatal authentication denied" >&2
    exit 1
    ;;
  restart_replay)
    echo "timeout waiting for transport ack" >&2
    exit 1
    ;;
  *)
    echo "unknown case: $CASE_NAME" >&2
    exit 1
    ;;
esac
OPENCLAW
  chmod +x "$mock_bin/openclaw"

  cat > "$mock_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
exit 1
TMUX
  chmod +x "$mock_bin/tmux"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
echo "mock gh unsupported: $*" >&2
exit 1
GH
  chmod +x "$mock_bin/gh"

  echo "$home_dir|$mock_bin|$state_dir"
}

run_case_success() {
  local env_meta home_dir mock_bin state_dir
  env_meta="$(setup_case_env success)"
  IFS='|' read -r home_dir mock_bin state_dir <<< "$env_meta"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_NOTIFY_STATE="$state_dir" \
    SGT_MOCK_NOTIFY_CASE="success" \
    bash --noprofile --norc -c 'set -euo pipefail; sgt mayor notify "success case" >/dev/null'

  [[ "$(cat "$state_dir/openclaw.count")" == "1" ]] || { echo "expected success case to call openclaw once" >&2; exit 1; }
  receipt_dir="$home_dir/sgt/.sgt/mayor-notify-receipts"
  [[ -d "$receipt_dir" ]] || { echo "expected receipt directory for success case" >&2; exit 1; }
  if [[ "$(find "$receipt_dir" -type f | wc -l | tr -d ' ')" != "1" ]]; then
    echo "expected exactly one success receipt" >&2
    exit 1
  fi
  receipt_file="$(find "$receipt_dir" -type f | head -n1)"
  grep -q '^CHANNEL=rigger$' "$receipt_file" || { echo "expected success receipt channel=rigger" >&2; exit 1; }
  grep -q '^ATTEMPT=1$' "$receipt_file" || { echo "expected success receipt attempt=1" >&2; exit 1; }
  grep -q '^OUTCOME=delivered$' "$receipt_file" || { echo "expected success receipt delivered outcome" >&2; exit 1; }
}

run_case_positive_ack_variant() {
  local case_name="$1" expected_matcher="$2" notify_message="$3"
  local env_meta home_dir mock_bin state_dir receipt_dir receipt_file decision_log
  env_meta="$(setup_case_env "$case_name")"
  IFS='|' read -r home_dir mock_bin state_dir <<< "$env_meta"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_NOTIFY_STATE="$state_dir" \
    SGT_MOCK_NOTIFY_CASE="$case_name" \
    bash --noprofile --norc -c "set -euo pipefail; sgt mayor notify \"$notify_message\" >/dev/null"

  [[ "$(cat "$state_dir/openclaw.count")" == "1" ]] || { echo "expected $case_name to send exactly once" >&2; exit 1; }
  receipt_dir="$home_dir/sgt/.sgt/mayor-notify-receipts"
  [[ -d "$receipt_dir" ]] || { echo "expected receipt directory for $case_name" >&2; exit 1; }
  receipt_file="$(find "$receipt_dir" -type f | head -n1)"
  grep -q '^OUTCOME=delivered$' "$receipt_file" || { echo "expected delivered outcome for $case_name" >&2; exit 1; }
  decision_log="$home_dir/sgt/.sgt/mayor-decisions.log"
  grep -q "MAYOR NOTIFY RECEIPT .*outcome=delivered .*matcher=$expected_matcher" "$decision_log" || {
    echo "expected matcher=$expected_matcher in decision log for $case_name" >&2
    exit 1
  }
}

run_case_transient_then_success() {
  local env_meta home_dir mock_bin state_dir decision_log
  env_meta="$(setup_case_env transient_then_success)"
  IFS='|' read -r home_dir mock_bin state_dir <<< "$env_meta"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_NOTIFY_STATE="$state_dir" \
    SGT_MOCK_NOTIFY_CASE="transient_then_success" \
    bash --noprofile --norc -c 'set -euo pipefail; sgt mayor notify "transient retry case" >/dev/null'

  [[ "$(cat "$state_dir/openclaw.count")" == "2" ]] || { echo "expected transient case to retry once" >&2; exit 1; }
  receipt_dir="$home_dir/sgt/.sgt/mayor-notify-receipts"
  if [[ "$(find "$receipt_dir" -type f | wc -l | tr -d ' ')" != "2" ]]; then
    echo "expected two receipts (attempt 1 + retry) for transient case" >&2
    exit 1
  fi
  grep -q '^OUTCOME=transport-failure$' "$receipt_dir"/*.state || { echo "expected transient case attempt 1 transport-failure receipt" >&2; exit 1; }
  grep -q '^OUTCOME=delivered$' "$receipt_dir"/*.state || { echo "expected transient case retry delivered receipt" >&2; exit 1; }
  decision_log="$home_dir/sgt/.sgt/mayor-decisions.log"
  grep -q 'MAYOR NOTIFY RECEIPT .*attempt=1 .*outcome=transport-failure' "$decision_log" || {
    echo "expected transient case decision-log entry for failed attempt" >&2
    exit 1
  }
  grep -q 'MAYOR NOTIFY RECEIPT .*attempt=1 .*reason=transport-transient-failure .*matcher=transient-transport-pattern' "$decision_log" || {
    echo "expected transient case attempt 1 matcher/reason context in decision log" >&2
    exit 1
  }
  grep -q 'MAYOR NOTIFY RECEIPT .*attempt=2 .*outcome=delivered' "$decision_log" || {
    echo "expected transient case decision-log entry for retry success" >&2
    exit 1
  }
  grep -q 'MAYOR NOTIFY RECEIPT .*attempt=2 .*reason=ack-verified .*matcher=ack-assignment' "$decision_log" || {
    echo "expected transient case attempt 2 matcher/reason context in decision log" >&2
    exit 1
  }
}

run_case_hard_failure_deduped_escalation() {
  local env_meta home_dir mock_bin state_dir decision_log
  env_meta="$(setup_case_env hard_failure)"
  IFS='|' read -r home_dir mock_bin state_dir <<< "$env_meta"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_NOTIFY_STATE="$state_dir" \
    SGT_MOCK_NOTIFY_CASE="hard_failure" \
    bash --noprofile --norc -c 'set -euo pipefail; sgt mayor notify "hard failure case" >/dev/null || true'

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_NOTIFY_STATE="$state_dir" \
    SGT_MOCK_NOTIFY_CASE="hard_failure" \
    bash --noprofile --norc -c 'set -euo pipefail; sgt mayor notify "hard failure case" >/dev/null || true'

  [[ "$(cat "$state_dir/openclaw.count")" == "1" ]] || { echo "expected hard failure replay to stay deduped at one send attempt" >&2; exit 1; }
  decision_log="$home_dir/sgt/.sgt/mayor-decisions.log"
  if [[ "$(grep -c 'MAYOR NOTIFY ESCALATE reason=notify-transport-failure .*raw_reason=notify-transport-hard-failure .*matcher=hard-transport-pattern' "$decision_log")" -ne 1 ]]; then
    echo "expected exactly one hard-failure escalation decision with normalized reason and matcher" >&2
    exit 1
  fi
  if [[ "$(grep -c 'MAYOR NOTIFY SKIP reason=notify-retry-budget-exhausted-escalation-deduped .*normalized_reason=notify-transport-failure .*matcher=hard-transport-pattern' "$decision_log")" -ne 1 ]]; then
    echo "expected one deduped replay skip decision with matcher context" >&2
    exit 1
  fi
}

run_case_restart_replay() {
  local env_meta home_dir mock_bin state_dir decision_log
  env_meta="$(setup_case_env restart_replay)"
  IFS='|' read -r home_dir mock_bin state_dir <<< "$env_meta"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_NOTIFY_STATE="$state_dir" \
    SGT_MOCK_NOTIFY_CASE="restart_replay" \
    bash --noprofile --norc -c 'set -euo pipefail; sgt mayor notify "restart replay case" >/dev/null || true'

  [[ "$(cat "$state_dir/openclaw.count")" == "2" ]] || { echo "expected restart case first run to consume one retry (two sends)" >&2; exit 1; }

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_NOTIFY_STATE="$state_dir" \
    SGT_MOCK_NOTIFY_CASE="restart_replay" \
    bash --noprofile --norc -c 'set -euo pipefail; sgt mayor notify "restart replay case" >/dev/null || true'

  [[ "$(cat "$state_dir/openclaw.count")" == "2" ]] || { echo "expected restart replay to avoid additional sends after retry budget exhausted" >&2; exit 1; }
  decision_log="$home_dir/sgt/.sgt/mayor-decisions.log"
  grep -q 'MAYOR NOTIFY SKIP reason=notify-retry-budget-exhausted-escalation-deduped .*normalized_reason=notify-transport-failure .*raw_reason=transport-transient-failure .*matcher=transient-transport-pattern' "$decision_log" || {
    echo "expected restart replay deduped escalation decision to preserve matcher context" >&2
    exit 1
  }
}

run_case_non_ack_retry_and_escalate() {
  local env_meta home_dir mock_bin state_dir decision_log
  env_meta="$(setup_case_env non_ack_reply)"
  IFS='|' read -r home_dir mock_bin state_dir <<< "$env_meta"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_NOTIFY_STATE="$state_dir" \
    SGT_MOCK_NOTIFY_CASE="non_ack_reply" \
    bash --noprofile --norc -c 'set -euo pipefail; sgt mayor notify "non-ack case" >/dev/null || true'

  [[ "$(cat "$state_dir/openclaw.count")" == "2" ]] || { echo "expected non-ack case to retry once before escalation" >&2; exit 1; }
  decision_log="$home_dir/sgt/.sgt/mayor-decisions.log"
  grep -q 'MAYOR NOTIFY RECEIPT .*attempt=1 .*outcome=missing-ack .*matcher=no-ack-pattern' "$decision_log" || {
    echo "expected attempt 1 missing-ack matcher in non-ack case" >&2
    exit 1
  }
  grep -q 'MAYOR NOTIFY RECEIPT .*attempt=2 .*outcome=missing-ack .*matcher=no-ack-pattern' "$decision_log" || {
    echo "expected attempt 2 missing-ack matcher in non-ack case" >&2
    exit 1
  }
  if [[ "$(grep -c 'MAYOR NOTIFY ESCALATE reason=notify-missing-ack .*raw_reason=notify-missing-ack .*matcher=no-ack-pattern' "$decision_log")" -ne 1 ]]; then
    echo "expected one notify-missing-ack escalation decision with matcher context in non-ack case" >&2
    exit 1
  fi
}

run_case_success
run_case_positive_ack_variant ack_copy copy-token "copy ack variant case"
run_case_positive_ack_variant ack_ack ack-token "ack token variant case"
run_case_positive_ack_variant ack_received received-token "received token variant case"
run_case_positive_ack_variant ack_roger roger-token "roger token variant case"
run_case_transient_then_success
run_case_hard_failure_deduped_escalation
run_case_restart_replay
run_case_non_ack_retry_and_escalate

echo "ALL TESTS PASSED"
