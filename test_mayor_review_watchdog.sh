#!/usr/bin/env bash
# test_mayor_review_watchdog.sh — Regression checks for REVIEW_UNCLEAR watchdog threshold boundary + dedupe.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/sgt/.sgt/merge-queue"

bash -s "$SGT_SCRIPT" "$HOME_DIR" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
HOME_DIR="$2"
SGT_CONFIG="$HOME_DIR/sgt/.sgt"
SGT_MAYOR_REVIEW_WATCHDOG_STATE="$SGT_CONFIG/mayor-review-watchdog.state"
SGT_MAYOR_REVIEW_UNCLEAR_STALE_SECS=120

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _mayor_review_unclear_stale_secs)"
eval "$(extract_fn _mayor_review_watchdog_signature)"
eval "$(extract_fn _mayor_should_notify_review_watchdog)"
eval "$(extract_fn _mayor_review_watchdog_collect_stale)"
eval "$(extract_fn _mayor_review_watchdog_status_snapshot)"

mkdir -p "$SGT_CONFIG/merge-queue"
cat > "$SGT_CONFIG/merge-queue/boundary-hit" <<MQ
RIG=test
REPO=https://github.com/acme/demo
PR=101
ISSUE=88
HEAD_SHA=abc101
REVIEW_STATE=REVIEW_UNCLEAR
REVIEW_UNCLEAR_SINCE=880
MQ
cat > "$SGT_CONFIG/merge-queue/boundary-miss" <<MQ
RIG=test
REPO=https://github.com/acme/demo
PR=102
ISSUE=89
HEAD_SHA=abc102
REVIEW_STATE=REVIEW_UNCLEAR
REVIEW_UNCLEAR_SINCE=881
MQ

mapfile -t boundary_lines < <(_mayor_review_watchdog_collect_stale "1000" "$(_mayor_review_unclear_stale_secs)")
if [[ "${#boundary_lines[@]}" -ne 1 ]]; then
  echo "expected exactly one stale REVIEW_UNCLEAR queue item at threshold boundary" >&2
  exit 1
fi
if [[ "${boundary_lines[0]}" != boundary-hit*"|101|https://github.com/acme/demo|88|REVIEW_UNCLEAR|880|120|abc101|120" ]]; then
  echo "unexpected boundary-hit payload: ${boundary_lines[0]}" >&2
  exit 1
fi

rm -f "$SGT_CONFIG/merge-queue"/*
now_epoch="$(date +%s)"
cat > "$SGT_CONFIG/merge-queue/status-a" <<MQ
RIG=test
REPO=https://github.com/acme/demo
PR=201
ISSUE=98
HEAD_SHA=head201
REVIEW_STATE=REVIEW_UNCLEAR
REVIEW_UNCLEAR_SINCE=$((now_epoch - 130))
MQ
cat > "$SGT_CONFIG/merge-queue/status-b" <<MQ
RIG=test
REPO=https://github.com/acme/demo
PR=202
ISSUE=99
HEAD_SHA=head202
REVIEW_STATE=REVIEW_UNCLEAR
REVIEW_UNCLEAR_SINCE=$((now_epoch - 121))
MQ
IFS='|' read -r status_count status_oldest status_threshold <<< "$(_mayor_review_watchdog_status_snapshot)"
if [[ "$status_count" != "2" ]]; then
  echo "expected watchdog status to surface two stale REVIEW_UNCLEAR items" >&2
  exit 1
fi
if [[ "$status_threshold" != "120" ]]; then
  echo "expected watchdog status to surface threshold=120" >&2
  exit 1
fi
if [[ ! "$status_oldest" =~ ^[0-9]+$ || "$status_oldest" -lt 130 ]]; then
  echo "expected watchdog status to surface oldest stale age" >&2
  exit 1
fi

if ! _mayor_should_notify_review_watchdog "test" "https://github.com/acme/demo" "201" "REVIEW_UNCLEAR" "100" "head201"; then
  echo "expected first REVIEW_UNCLEAR transition to notify" >&2
  exit 1
fi
if _mayor_should_notify_review_watchdog "test" "https://github.com/acme/demo" "201" "REVIEW_UNCLEAR" "100" "head201"; then
  echo "expected duplicate REVIEW_UNCLEAR transition to be deduped" >&2
  exit 1
fi
if ! _mayor_should_notify_review_watchdog "test" "https://github.com/acme/demo" "201" "REVIEW_UNCLEAR" "101" "head201"; then
  echo "expected REVIEW_UNCLEAR timestamp transition to notify" >&2
  exit 1
fi
if _mayor_should_notify_review_watchdog "test" "https://github.com/acme/demo" "201" "REVIEW_UNCLEAR" "101" "head201"; then
  echo "expected duplicate notify to remain suppressed after transition" >&2
  exit 1
fi
BASH

if ! grep -q 'review watchdog: .*stalled REVIEW_UNCLEAR.*oldest=.*threshold>=' "$SGT_SCRIPT"; then
  echo "expected status output path to surface REVIEW_UNCLEAR watchdog age + threshold" >&2
  exit 1
fi
if ! grep -q 'mayor escalated: refinery review stalled' "$SGT_SCRIPT"; then
  echo "expected mayor escalation notify message for stalled REVIEW_UNCLEAR" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
