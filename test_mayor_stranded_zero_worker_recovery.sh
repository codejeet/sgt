#!/usr/bin/env bash
# test_mayor_stranded_zero_worker_recovery.sh — Mayor should recover stranded actionable rigs or log an explicit blocked reason.

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

eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn log_event)"
eval "$(extract_fn _plan_target_concurrency)"
eval "$(extract_fn _mayor_recover_stranded_actionable_rig)"

export SGT_LOG="$TMP_ROOT/sgt.log"
: > "$SGT_LOG"

_repo_owner_repo() { printf '%s\n' "${1#https://github.com/}"; }
_mayor_rig_hibernated() { return 1; }
_mayor_rig_activity_snapshot() { printf '%s\n' 'active|open_issues=2 open_prs=0 active_polecats=0 merge_queue=0 pending_plan_requests=0|2|0|0|0|0|not_declared|not_declared'; }
_plan_effective_file_path() { printf '%s\n' "$TMP_ROOT/SGT_PLAN.json"; }
_plan_file_path() { printf '%s\n' "$TMP_ROOT/SGT_PLAN.json"; }
_issue_backend_dispatch_limited_reason() { return 1; }
_resling_find_existing_issue_polecat() { return 1; }
_sweep_watchdog_find_open_pr_for_issue() { return 1; }
_ai_backend_default() { printf '%s\n' 'codex'; }

cat > "$TMP_ROOT/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 2 },
  "tasks": []
}
JSON

gh() {
  if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
    printf '77\tRecover capture lane\n78\tSecond lane\n'
    return 0
  fi
  echo "unexpected gh call: $*" >&2
  return 1
}

_RESLING_LAST_POLECAT=""
_resling_existing_issue() {
  local issue="${2:-}"
  if [[ "$issue" == "77" ]]; then
    _RESLING_LAST_POLECAT="demo-77"
    return 0
  fi
  if [[ "$issue" == "78" ]]; then
    _RESLING_LAST_POLECAT="demo-78"
    return 0
  fi
  echo "[resling] stale event (mayor-zero-worker-recovery) for issue #$issue — skipping: issue already closed"
  return 1
}

_mayor_recover_stranded_actionable_rig demo https://github.com/acme/demo

[[ "${_MAYOR_STRANDED_RECOVERY_DISPATCHED:-0}" == "2" ]]
[[ "${_MAYOR_STRANDED_RECOVERY_BLOCKED:-0}" == "0" ]]
grep -q 'MAYOR_STRANDED_RIG_RECOVERY_DISPATCH issue=#77 rig=demo repo=acme/demo reason_code=no-active-polecat-no-open-pr polecat=demo-77' "$SGT_LOG"
grep -q 'MAYOR_STRANDED_RIG_RECOVERY_DISPATCH issue=#78 rig=demo repo=acme/demo reason_code=no-active-polecat-no-open-pr polecat=demo-78' "$SGT_LOG"

_mayor_rig_activity_snapshot() { printf '%s\n' 'active|open_issues=1 open_prs=0 active_polecats=0 merge_queue=0 pending_plan_requests=0|1|0|0|0|0|not_declared|not_declared'; }
gh() {
  if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
    printf '88\tBlocked lane\n'
    return 0
  fi
  echo "unexpected gh call: $*" >&2
  return 1
}
_resling_existing_issue() {
  echo "[resling] stale event (mayor-zero-worker-recovery) for issue #88 — skipping: issue already closed"
  return 1
}

_mayor_recover_stranded_actionable_rig demo https://github.com/acme/demo

[[ "${_MAYOR_STRANDED_RECOVERY_DISPATCHED:-0}" == "0" ]]
[[ "${_MAYOR_STRANDED_RECOVERY_BLOCKED:-0}" == "1" ]]
grep -q '88|stale-event|' <<< "${_MAYOR_STRANDED_RECOVERY_DETAILS:-}"
grep -q 'MAYOR_STRANDED_RIG_RECOVERY_BLOCKED issue=#88 rig=demo repo=acme/demo reason_code=stale-event' "$SGT_LOG"

grep -q '_mayor_recover_stranded_actionable_rig "\$rname" "\$repo"' "$SGT_SCRIPT"

echo "PASS: mayor stranded zero-worker recovery"
