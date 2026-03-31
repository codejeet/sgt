#!/usr/bin/env bash
# test_president_cutover_migration_guard.sh — Verify per-rig cutover retires legacy shared mayor state without disturbing durable rig truth.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _president_runtime_dir)"
eval "$(extract_fn _mayor_architecture)"
eval "$(extract_fn _mayor_architecture_per_rig)"
eval "$(extract_fn _legacy_shared_mayor_session_name)"
eval "$(extract_fn _mayor_refresh_transient_entries)"
eval "$(extract_fn _mayor_cutover_archive_dir)"
eval "$(extract_fn _mayor_cutover_token)"
eval "$(extract_fn _mayor_cutover_transient_entries)"
eval "$(extract_fn _mayor_cutover_retire_shared_mayor)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_MAYOR_ARCHITECTURE=per-rig
mkdir -p "$SGT_CONFIG" "$SGT_CONFIG/plan-state" "$SGT_CONFIG/polecats" "$SGT_CONFIG/mayors/demo"

EVENT_LOG="$TMP_ROOT/events.log"
SESSIONS_FILE="$TMP_ROOT/tmux-sessions"
printf 'sgt-mayor\n' > "$SESSIONS_FILE"

log_event() {
  printf '%s\n' "$*" >> "$EVENT_LOG"
}

_escape_quotes() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" ]]; then
    grep -qx "${3:-}" "$SESSIONS_FILE" 2>/dev/null
    return $?
  fi
  if [[ "${1:-}" == "kill-session" && "${2:-}" == "-t" ]]; then
    local tmp="${SESSIONS_FILE}.tmp.$$"
    grep -vx "${3:-}" "$SESSIONS_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$SESSIONS_FILE"
    return 0
  fi
  return 1
}

printf 'shared dispatch snapshot\n' > "$SGT_CONFIG/mayor-dispatch-snapshot.tsv"
printf 'shared watchdog state\n' > "$SGT_CONFIG/mayor-review-watchdog.state"
printf 'shared decisions\n' > "$SGT_CONFIG/mayor-decisions.log"
printf 'shared lock\n' > "$SGT_CONFIG/mayor.lock"
printf 'shared workspace\n' > "$SGT_CONFIG/mayor-workspace"
rm -f "$SGT_CONFIG/mayor-workspace"
mkdir -p "$SGT_CONFIG/mayor-workspace" "$SGT_CONFIG/handoffs/h1"
printf 'workspace context\n' > "$SGT_CONFIG/mayor-workspace/CLAUDE.md"
printf 'old handoff\n' > "$SGT_CONFIG/handoffs/h1/handoff.md"
mkfifo "$SGT_CONFIG/mayor.fifo"

printf '{"completion":{"status":"pending"}}\n' > "$SGT_CONFIG/plan-state/demo.json"
printf 'RIG=demo\nISSUE=42\n' > "$SGT_CONFIG/polecats/demo-cat"
printf 'scoped heartbeat\n' > "$SGT_CONFIG/mayors/demo/mayor-heartbeat.state"

_mayor_cutover_retire_shared_mayor

if grep -qx 'sgt-mayor' "$SESSIONS_FILE" 2>/dev/null; then
  echo "expected shared mayor session to be retired during cutover" >&2
  exit 1
fi

cutover_root="$SGT_CONFIG/president/cutovers"
if [[ ! -d "$cutover_root" ]]; then
  echo "expected cutover archive root to be created" >&2
  exit 1
fi

mapfile -t cutover_dirs < <(find "$cutover_root" -mindepth 1 -maxdepth 1 -type d | sort)
if [[ "${#cutover_dirs[@]}" -ne 1 ]]; then
  echo "expected exactly one cutover archive, got ${#cutover_dirs[@]}" >&2
  exit 1
fi

archive_dir="${cutover_dirs[0]}"
for archived in \
  "$archive_dir/mayor-dispatch-snapshot.tsv" \
  "$archive_dir/mayor-review-watchdog.state" \
  "$archive_dir/mayor-decisions.log" \
  "$archive_dir/mayor.lock" \
  "$archive_dir/mayor.fifo" \
  "$archive_dir/mayor-workspace/CLAUDE.md" \
  "$archive_dir/handoffs/h1/handoff.md" \
  "$archive_dir/cutover.env"; do
  if [[ ! -e "$archived" ]]; then
    echo "expected archived cutover entry missing: $archived" >&2
    exit 1
  fi
done

for removed in \
  "$SGT_CONFIG/mayor-dispatch-snapshot.tsv" \
  "$SGT_CONFIG/mayor-review-watchdog.state" \
  "$SGT_CONFIG/mayor-decisions.log" \
  "$SGT_CONFIG/mayor.lock" \
  "$SGT_CONFIG/mayor.fifo" \
  "$SGT_CONFIG/mayor-workspace" \
  "$SGT_CONFIG/handoffs"; do
  if [[ -e "$removed" ]]; then
    echo "expected shared transient to be removed from live root: $removed" >&2
    exit 1
  fi
done

for durable in \
  "$SGT_CONFIG/plan-state/demo.json" \
  "$SGT_CONFIG/polecats/demo-cat" \
  "$SGT_CONFIG/mayors/demo/mayor-heartbeat.state"; do
  if [[ ! -e "$durable" ]]; then
    echo "expected durable rig truth to remain in place: $durable" >&2
    exit 1
  fi
done

if ! grep -q 'MAYOR_HIERARCHY_CUTOVER retired_shared_session=1 archived_entries=' "$EVENT_LOG"; then
  echo "expected durable cutover event log entry" >&2
  exit 1
fi

_mayor_cutover_retire_shared_mayor || true
mapfile -t cutover_dirs_after < <(find "$cutover_root" -mindepth 1 -maxdepth 1 -type d | sort)
if [[ "${#cutover_dirs_after[@]}" -ne 1 ]]; then
  echo "expected no additional cutover archive on no-op replay" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
