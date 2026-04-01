#!/usr/bin/env bash
# test_mayor_acceptance_blocker_regression.sh — Prevent idle-green when acceptance remains unresolved.

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

eval "$(extract_fn _acceptance_blockers_dir)"
eval "$(extract_fn _acceptance_blocker_dir)"
eval "$(extract_fn _acceptance_blocker_meta_path)"
eval "$(extract_fn _acceptance_blocker_evidence_path)"
eval "$(extract_fn _acceptance_blocker_id)"
eval "$(extract_fn _acceptance_blocker_title)"
eval "$(extract_fn _one_line)"
eval "$(extract_fn _normalize_label)"
eval "$(extract_fn _acceptance_blocker_severity_class)"
eval "$(extract_fn _acceptance_blocker_dedupe_key)"
eval "$(extract_fn _acceptance_blocker_write)"
eval "$(extract_fn _acceptance_blocker_ids)"
eval "$(extract_fn _acceptance_blocker_list_active)"
eval "$(extract_fn _mayor_rig_actionable_work_counts)"
eval "$(extract_fn _mayor_acceptance_blocker_scan)"

SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_ACCEPTANCE_BLOCKERS="$SGT_CONFIG/acceptance-blockers"
mkdir -p "$SGT_ACCEPTANCE_BLOCKERS"

rig_repo() {
  printf '%s\n' "https://github.com/acme/demo"
}

_active_polecat_count() {
  printf '%s\n' "${POLECAT_COUNT:-0}"
}

_plan_request_list_pending() {
  local count="${PLAN_PENDING_COUNT:-0}" i=0
  while (( i < count )); do
    printf 'req-%s|demo|pending|2026-03-11T00:00:00Z|requester|/tmp/prompt.md\n' "$i"
    i=$((i + 1))
  done
}

gh() {
  if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
    printf '%s\n' "${PR_COUNT:-0}"
    return 0
  fi
  if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
    printf '%s\n' "${ISSUE_COUNT:-0}"
    return 0
  fi
  return 1
}

blocker_id="$(_acceptance_blocker_write "demo" "Verified acceptance still red after merge" "verifier-7" "argv")"
[[ -n "$blocker_id" ]] || { echo "expected blocker id" >&2; exit 1; }

PR_COUNT=0
ISSUE_COUNT=0
POLECAT_COUNT=0
PLAN_PENDING_COUNT=0
idle_scan="$(_mayor_acceptance_blocker_scan)"
if [[ "$idle_scan" != *"needs-ai-followup"* ]]; then
  echo "expected idle rig with open acceptance blocker to require AI follow-up" >&2
  echo "$idle_scan" >&2
  exit 1
fi

ISSUE_COUNT=1
tracked_scan="$(_mayor_acceptance_blocker_scan)"
if [[ "$tracked_scan" != *"tracking-existing-work"* ]]; then
  echo "expected rig with open work to avoid idle-green escalation state" >&2
  echo "$tracked_scan" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
BASH
