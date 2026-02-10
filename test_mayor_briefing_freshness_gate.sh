#!/usr/bin/env bash
# test_mayor_briefing_freshness_gate.sh — Regression checks for mayor AI briefing freshness gate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

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

eval "$(extract_fn _mayor_briefing_stale_secs)"
eval "$(extract_fn _mayor_briefing_snapshot)"
eval "$(extract_fn _mayor_prepare_briefing_for_cycle)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export SGT_CONFIG="$TMP_ROOT/.sgt"
mkdir -p "$SGT_CONFIG"
export SGT_MAYOR_BRIEFING_STALE_SECS=5
EVENT_LOG="$TMP_ROOT/events.log"

log_event() {
  echo "$*" >> "$EVENT_LOG"
}

_escape_quotes() {
  printf "%s" "${1:-}"
}

write_briefing() {
  local epoch="$1"
  local iso
  iso="$(date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$SGT_CONFIG/mayor-briefing.md" <<EOF_B
# SGT System Briefing

generated_at: $iso
generated_at_epoch: $epoch

## System Status
ok
EOF_B
}

BUILD_CALLS_FILE="$TMP_ROOT/build_calls.count"
set_build_calls() {
  printf '%s\n' "$1" > "$BUILD_CALLS_FILE"
}
get_build_calls() {
  cat "$BUILD_CALLS_FILE"
}
inc_build_calls() {
  local n
  n="$(get_build_calls)"
  n=$((n + 1))
  set_build_calls "$n"
  echo "$n"
}

# Case 1: stale preexisting briefing is detected and refreshed.
old_epoch=$(( $(date +%s) - 120 ))
write_briefing "$old_epoch"
set_build_calls 0
_mayor_build_briefing() {
  inc_build_calls >/dev/null
  write_briefing "$(date +%s)"
  echo "$SGT_CONFIG/mayor-briefing.md"
}
out="$(_mayor_prepare_briefing_for_cycle)"
IFS='|' read -r path status generated_at age threshold stale_detected flow_path <<< "$out"
[[ "$status" == "fresh" ]] || { echo "expected fresh status after stale refresh" >&2; exit 1; }
[[ "$stale_detected" == "true" ]] || { echo "expected stale detection on stale preexisting file" >&2; exit 1; }
[[ "$flow_path" == "refreshed" ]] || { echo "expected refreshed path for stale preexisting file" >&2; exit 1; }
[[ "$(get_build_calls)" -eq 1 ]] || { echo "expected exactly one rebuild for stale preexisting file" >&2; exit 1; }
if ! grep -q 'MAYOR_BRIEFING_GATE stale_detected=true path=refreshed status=fresh' "$EVENT_LOG"; then
  echo "expected structured stale-detected refreshed path log" >&2
  exit 1
fi

# Case 2: concurrent-update race simulation (fresh precheck, stale write wins, auto-refresh recovers).
: > "$EVENT_LOG"
write_briefing "$(date +%s)"
set_build_calls 0
_mayor_build_briefing() {
  local n
  n="$(inc_build_calls)"
  if [[ "$n" -eq 1 ]]; then
    write_briefing "$(( $(date +%s) - 90 ))"
  else
    write_briefing "$(date +%s)"
  fi
  echo "$SGT_CONFIG/mayor-briefing.md"
}
out="$(_mayor_prepare_briefing_for_cycle)"
IFS='|' read -r path status generated_at age threshold stale_detected flow_path <<< "$out"
[[ "$status" == "fresh" ]] || { echo "expected fresh status after race refresh" >&2; exit 1; }
[[ "$stale_detected" == "false" ]] || { echo "expected no stale-precheck detection in race simulation" >&2; exit 1; }
[[ "$flow_path" == "refreshed" ]] || { echo "expected refreshed path in race simulation" >&2; exit 1; }
[[ "$(get_build_calls)" -eq 2 ]] || { echo "expected exactly two builds in race simulation" >&2; exit 1; }
if ! grep -q 'MAYOR_BRIEFING_GATE stale_detected=false path=refreshed status=fresh' "$EVENT_LOG"; then
  echo "expected structured refreshed path log for race simulation" >&2
  exit 1
fi

# Case 3: stale snapshot cannot be repaired => abort.
: > "$EVENT_LOG"
write_briefing "$(date +%s)"
_mayor_build_briefing() {
  write_briefing "$(( $(date +%s) - 180 ))"
  echo "$SGT_CONFIG/mayor-briefing.md"
}
if out="$(_mayor_prepare_briefing_for_cycle)"; then
  echo "expected unrecoverable stale briefing to abort" >&2
  exit 1
fi
IFS='|' read -r path status generated_at age threshold stale_detected flow_path <<< "$out"
[[ "$flow_path" == "aborted" ]] || { echo "expected aborted path on unrecoverable stale briefing" >&2; exit 1; }
if ! grep -q 'MAYOR_BRIEFING_GATE stale_detected=false path=aborted status=stale' "$EVENT_LOG"; then
  echo "expected structured aborted path log when briefing remains stale" >&2
  exit 1
fi
BASH

if ! grep -q 'generated_at: \$now_iso' "$SGT_SCRIPT"; then
  echo "expected mayor briefing builder to stamp generated_at" >&2
  exit 1
fi

if ! grep -q 'generated_at_epoch: \$now_epoch' "$SGT_SCRIPT"; then
  echo "expected mayor briefing builder to stamp generated_at_epoch" >&2
  exit 1
fi

if ! grep -q '_mayor_prepare_briefing_for_cycle' "$SGT_SCRIPT"; then
  echo "expected mayor AI cycle to enforce briefing freshness gate" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
