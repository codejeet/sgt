#!/usr/bin/env bash
# test_mayor_ci_check_watchdog.sh — Regression checks for stale required-check watchdog threshold, dedupe window, and recovery reset.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/sgt/.sgt"

bash -s "$SGT_SCRIPT" "$HOME_DIR" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
HOME_DIR="$2"
SGT_CONFIG="$HOME_DIR/sgt/.sgt"
SGT_MAYOR_CI_CHECK_WATCHDOG_STATE="$SGT_CONFIG/mayor-ci-check-watchdog.state"
SGT_MAYOR_CI_CHECK_DEDUPE_SECS=120
SGT_MAYOR_CI_CHECK_STALE_SECS=120

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_wake_value)"
eval "$(extract_fn _mayor_ci_check_stale_secs)"
eval "$(extract_fn _mayor_ci_check_dedupe_secs)"
eval "$(extract_fn _mayor_ci_check_watchdog_key)"
eval "$(extract_fn _mayor_ci_check_watchdog_state_read)"
eval "$(extract_fn _mayor_ci_check_watchdog_state_upsert)"
eval "$(extract_fn _mayor_reset_ci_check_watchdog)"
eval "$(extract_fn _mayor_ci_check_watchdog_reset_pr_recovered)"
eval "$(extract_fn _mayor_should_notify_ci_check_watchdog)"
eval "$(extract_fn _mayor_ci_check_watchdog_collect_stale_for_pr)"

mapfile -t boundary_lines < <(
  _mayor_ci_check_watchdog_collect_stale_for_pr "demo-rig" "https://github.com/acme/demo" "77" "1000" "$(_mayor_ci_check_stale_secs)" <<'LINES'
build|QUEUED|880|https://github.com/acme/demo/actions/runs/123
lint|IN_PROGRESS|881|https://github.com/acme/demo/actions/runs/456
LINES
)

if [[ "${#boundary_lines[@]}" -ne 1 ]]; then
  echo "expected exactly one stale required check at threshold boundary" >&2
  exit 1
fi

if [[ "${boundary_lines[0]}" != "demo-rig|https://github.com/acme/demo|77|build|QUEUED|880|120|120|https://github.com/acme/demo/actions/runs/123|"* ]]; then
  echo "unexpected stale boundary payload: ${boundary_lines[0]}" >&2
  exit 1
fi

IFS='|' read -r _ _ _ _ _ _ _ _ _ boundary_key <<< "${boundary_lines[0]}"
if [[ -z "$boundary_key" ]]; then
  echo "expected stale payload to include watchdog key" >&2
  exit 1
fi

if ! _mayor_should_notify_ci_check_watchdog "$boundary_key"; then
  echo "expected first stale required-check escalation to notify" >&2
  exit 1
fi
if _mayor_should_notify_ci_check_watchdog "$boundary_key"; then
  echo "expected duplicate stale required-check escalation to be deduped in-window" >&2
  exit 1
fi

tmp_state="$(mktemp)"
awk -F'\t' 'BEGIN{OFS="\t"} { if ($1=="demo-rig|https://github.com/acme/demo|77|build") { $3=$3-121 } print }' "$SGT_MAYOR_CI_CHECK_WATCHDOG_STATE" > "$tmp_state"
mv "$tmp_state" "$SGT_MAYOR_CI_CHECK_WATCHDOG_STATE"

if ! _mayor_should_notify_ci_check_watchdog "$boundary_key"; then
  echo "expected stale required-check escalation to notify after dedupe window expires" >&2
  exit 1
fi

_mayor_ci_check_watchdog_collect_stale_for_pr "demo-rig" "https://github.com/acme/demo" "77" "1005" "$(_mayor_ci_check_stale_secs)" <<< ""

if grep -q "^demo-rig|https://github.com/acme/demo|77|build" "$SGT_MAYOR_CI_CHECK_WATCHDOG_STATE" 2>/dev/null; then
  echo "expected recovery/completion reset to clear required-check watchdog state for PR" >&2
  exit 1
fi

mapfile -t recovered_lines < <(
  _mayor_ci_check_watchdog_collect_stale_for_pr "demo-rig" "https://github.com/acme/demo" "77" "1010" "$(_mayor_ci_check_stale_secs)" <<'LINES'
build|QUEUED|880|https://github.com/acme/demo/actions/runs/123
LINES
)
if [[ "${#recovered_lines[@]}" -ne 1 ]]; then
  echo "expected recovered required check to become stale again after reset" >&2
  exit 1
fi

IFS='|' read -r _ _ _ _ _ _ _ _ _ recovered_key <<< "${recovered_lines[0]}"
if ! _mayor_should_notify_ci_check_watchdog "$recovered_key"; then
  echo "expected fresh stale required-check escalation after recovery reset" >&2
  exit 1
fi
BASH

if ! grep -q 'mayor escalated: required check stale .* stale_seconds=.* check_url=.* runbook_action=retry' "$SGT_SCRIPT"; then
  echo "expected stale required-check escalation message to include stale_seconds + check_url + runbook_action=retry" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
