#!/usr/bin/env bash
# test_mayor_briefing_missing_fallback.sh — Regression checks for missing mayor briefing fallback content.

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

eval "$(extract_fn _active_polecat_count)"
eval "$(extract_fn _mayor_merge_queue_count_for_rig)"
eval "$(extract_fn _deacon_heartbeat_stale_secs)"
eval "$(extract_fn _heartbeat_snapshot_file)"
eval "$(extract_fn _deacon_heartbeat_snapshot)"
eval "$(extract_fn _deacon_heartbeat_health)"
eval "$(extract_fn _mayor_live_status_briefing_fallback)"
eval "$(extract_fn _mayor_briefing_content_for_prompt)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export SGT_CONFIG="$TMP_ROOT/.sgt"
export SGT_POLECATS="$SGT_CONFIG/polecats"
export SGT_DEACON_HEARTBEAT="$SGT_CONFIG/deacon-heartbeat.json"
mkdir -p "$SGT_CONFIG/merge-queue" "$SGT_POLECATS"

cat > "$SGT_CONFIG/merge-queue/a.state" <<'MQ'
RIG=alpha
PR=11
MQ
cat > "$SGT_CONFIG/merge-queue/b.state" <<'MQ'
RIG=beta
PR=12
MQ

: > "$SGT_POLECATS/alpha-1"
: > "$SGT_POLECATS/alpha-2"
: > "$SGT_POLECATS/beta-1"

now_iso="$(date -Iseconds)"
cat > "$SGT_DEACON_HEARTBEAT" <<HB
{
  "timestamp": "$now_iso"
}
HB

EVENT_LOG="$TMP_ROOT/events.log"
log_event() {
  echo "$*" >> "$EVENT_LOG"
}

_escape_quotes() {
  printf '%s' "${1:-}"
}

cmd_status() {
  echo "LIVE STATUS OK"
}

MOCK_BIN="$TMP_ROOT/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" && "${3:-}" == "sgt-deacon" ]]; then
  exit 0
fi
exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"
export PATH="$MOCK_BIN:$PATH"

missing_path="$SGT_CONFIG/mayor-briefing.md"
stderr_file="$TMP_ROOT/fallback.err"
out="$(_mayor_briefing_content_for_prompt "$missing_path" 2>"$stderr_file")"

if [[ -s "$stderr_file" ]]; then
  echo "expected missing-briefing fallback to avoid stderr noise" >&2
  cat "$stderr_file" >&2
  exit 1
fi

if grep -qiE 'cat:|no such file' "$stderr_file"; then
  echo "unexpected cat/no-such-file stderr for missing briefing path" >&2
  exit 1
fi

grep -q '^# SGT System Briefing (fallback)$' <<< "$out" || { echo "expected fallback heading" >&2; exit 1; }
grep -q '^fallback_reason: briefing-unavailable$' <<< "$out" || { echo "expected fallback reason" >&2; exit 1; }
grep -q "^fallback_path: $missing_path$" <<< "$out" || { echo "expected fallback path marker" >&2; exit 1; }
grep -q 'deacon_status: on (session=on heartbeat_state=ok heartbeat_health=healthy' <<< "$out" || { echo "expected deacon health in fallback" >&2; exit 1; }
grep -q '^\- merge_queue_depth: 2$' <<< "$out" || { echo "expected merge queue depth in fallback" >&2; exit 1; }
grep -q '^\- active_polecats: 3$' <<< "$out" || { echo "expected active polecats in fallback" >&2; exit 1; }
grep -q '^LIVE STATUS OK$' <<< "$out" || { echo "expected live status block in fallback" >&2; exit 1; }
grep -q 'MAYOR_BRIEFING_FALLBACK reason=briefing-unavailable path=' "$EVENT_LOG" || { echo "expected fallback log event" >&2; exit 1; }

cat > "$missing_path" <<'BRIEF'
# Explicit Briefing
from-file
BRIEF

out_from_file="$(_mayor_briefing_content_for_prompt "$missing_path")"
if [[ "$out_from_file" != *"from-file"* ]]; then
  echo "expected existing briefing path to be used directly" >&2
  exit 1
fi
if [[ "$out_from_file" == *"fallback_reason:"* ]]; then
  echo "did not expect fallback content when briefing file exists" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
