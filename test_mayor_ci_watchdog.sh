#!/usr/bin/env bash
# test_mayor_ci_watchdog.sh — Regression checks for stale required CI watchdog boundary + dedupe window + recovery reset.

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
SGT_MAYOR_CI_WATCHDOG_STATE="$SGT_CONFIG/mayor-ci-watchdog.state"
SGT_MAYOR_CI_CHECK_STALE_SECS=120
SGT_MAYOR_CI_WATCHDOG_DEDUPE_SECS=300

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _mayor_ci_check_stale_secs)"
eval "$(extract_fn _mayor_ci_watchdog_dedupe_window_secs)"
eval "$(extract_fn _mayor_ci_watchdog_signature)"
eval "$(extract_fn _mayor_ci_watchdog_state_key)"
eval "$(extract_fn _mayor_should_notify_ci_watchdog)"
eval "$(extract_fn _mayor_ci_watchdog_reconcile_state)"
eval "$(extract_fn _mayor_ci_watchdog_collect_from_check_stream)"

# Threshold boundary: age==threshold is stale, age<threshold is not.
ts_hit="$(date -u -d '@880' +%Y-%m-%dT%H:%M:%SZ)"
ts_miss="$(date -u -d '@881' +%Y-%m-%dT%H:%M:%SZ)"
mapfile -t boundary_lines < <(
  {
    printf 'required-build\tQUEUED\t%s\thttps://checks.example/build\n' "$ts_hit"
    printf 'required-test\tIN_PROGRESS\t%s\thttps://checks.example/test\n' "$ts_miss"
  } | _mayor_ci_watchdog_collect_from_check_stream \
    "rig-a" "acme/demo" "101" "0" "https://github.com/acme/demo/pull/101" "unknown" "1000" "$(_mayor_ci_check_stale_secs)"
)
if [[ "${#boundary_lines[@]}" -ne 1 ]]; then
  echo "expected exactly one stale required check at threshold boundary" >&2
  exit 1
fi
if [[ "${boundary_lines[0]}" != "rig-a|acme/demo|101|0|required-build|QUEUED|880|120|120|https://checks.example/build|https://github.com/acme/demo/pull/101|unknown" ]]; then
  echo "unexpected boundary payload: ${boundary_lines[0]}" >&2
  exit 1
fi

# Dedupe window: one escalation per pr+check per dedupe window.
if ! _mayor_should_notify_ci_watchdog "rig-a" "acme/demo" "101" "required-build" "QUEUED" "880" "https://checks.example/build" "1000"; then
  echo "expected first stale required check escalation to notify" >&2
  exit 1
fi
if _mayor_should_notify_ci_watchdog "rig-a" "acme/demo" "101" "required-build" "QUEUED" "880" "https://checks.example/build" "1299"; then
  echo "expected duplicate stale required check escalation inside dedupe window to suppress" >&2
  exit 1
fi
if ! _mayor_should_notify_ci_watchdog "rig-a" "acme/demo" "101" "required-build" "QUEUED" "880" "https://checks.example/build" "1300"; then
  echo "expected stale required check escalation to re-notify at dedupe window boundary" >&2
  exit 1
fi

# Recovery/completion reset: when item no longer stale, dedupe entry is removed.
if ! _mayor_should_notify_ci_watchdog "rig-a" "acme/demo" "102" "required-lint" "IN_PROGRESS" "1700" "https://checks.example/lint" "2000"; then
  echo "expected first required-lint escalation to notify" >&2
  exit 1
fi
if _mayor_should_notify_ci_watchdog "rig-a" "acme/demo" "102" "required-lint" "IN_PROGRESS" "1700" "https://checks.example/lint" "2001"; then
  echo "expected duplicate required-lint escalation to suppress before recovery" >&2
  exit 1
fi
_mayor_ci_watchdog_reconcile_state
if ! _mayor_should_notify_ci_watchdog "rig-a" "acme/demo" "102" "required-lint" "IN_PROGRESS" "1700" "https://checks.example/lint" "2002"; then
  echo "expected recovery reset to clear dedupe and allow re-notify" >&2
  exit 1
fi
BASH

if ! grep -q 'ci watchdog: .*stalled required checks' "$SGT_SCRIPT"; then
  echo "expected status output path to surface CI watchdog health" >&2
  exit 1
fi
if ! grep -q 'mayor escalated: stale required check' "$SGT_SCRIPT"; then
  echo "expected mayor escalation notify message for stale required checks" >&2
  exit 1
fi
if ! grep -q 'check_url=' "$SGT_SCRIPT"; then
  echo "expected stale required check escalation context to include check_url" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
