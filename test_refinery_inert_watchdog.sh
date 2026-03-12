#!/usr/bin/env bash
# test_refinery_inert_watchdog.sh — Regression checks for queued-work refinery stall restart + status visibility.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "=== deacon queued-work refinery watchdog decision ==="
bash -s "$SGT_SCRIPT" "$TMP_ROOT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
TMP_ROOT="$2"
HOME_DIR="$TMP_ROOT/helper-home"
SGT_ROOT="$HOME_DIR/sgt"
SGT_CONFIG="$SGT_ROOT/.sgt"
mkdir -p "$SGT_CONFIG/merge-queue"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _agent_heartbeat_stale_secs)"
eval "$(extract_fn _agent_heartbeat_path)"
eval "$(extract_fn _merge_queue_count_for_rig)"
eval "$(extract_fn _merge_queue_oldest_age_for_rig)"
eval "$(extract_fn _heartbeat_snapshot_file)"
eval "$(extract_fn _agent_heartbeat_snapshot)"
eval "$(extract_fn _deacon_refinery_watchdog_state)"

old_ts="$(date -u -d "@$(( $(date +%s) - 240 ))" +%Y-%m-%dT%H:%M:%S+00:00)"
cat > "$SGT_CONFIG/refinery-demo-heartbeat.json" <<HB
{
  "timestamp": "$old_ts",
  "cycle": 4,
  "pid": 4242,
  "agent": "refinery",
  "rig": "demo"
}
HB

cat > "$SGT_CONFIG/merge-queue/demo-pr123" <<MQ
RIG=demo
PR=123
QUEUED=$(date -u -d "@$(( $(date +%s) - 600 ))" +%Y-%m-%dT%H:%M:%S+00:00)
MQ

IFS='|' read -r action reason queue_count oldest_age hb_age hb_ts hb_state hb_stale_secs <<< "$(_deacon_refinery_watchdog_state demo)"

if [[ "$action" != "restart" || "$reason" != "heartbeat-stale" ]]; then
  echo "expected restart|heartbeat-stale, got $action|$reason" >&2
  exit 1
fi
if [[ "$queue_count" != "1" ]]; then
  echo "expected queue_count=1, got $queue_count" >&2
  exit 1
fi
if [[ ! "$oldest_age" =~ ^[0-9]+$ || "$oldest_age" -lt 500 ]]; then
  echo "expected oldest queue age >= 500s, got $oldest_age" >&2
  exit 1
fi
if [[ ! "$hb_age" =~ ^[0-9]+$ || "$hb_age" -lt "$hb_stale_secs" ]]; then
  echo "expected stale heartbeat age >= threshold, got age=$hb_age threshold=$hb_stale_secs" >&2
  exit 1
fi

rm -f "$SGT_CONFIG/merge-queue/demo-pr123"
IFS='|' read -r action reason queue_count oldest_age hb_age hb_ts hb_state hb_stale_secs <<< "$(_deacon_refinery_watchdog_state demo)"
if [[ "$action" != "ok" || "$reason" != "queue-empty" ]]; then
  echo "expected ok|queue-empty once queue is clear, got $action|$reason" >&2
  exit 1
fi
BASH

echo "=== status surfaces degraded refinery with queued backlog ==="
HOME_DIR="$TMP_ROOT/status-home"
MOCK_BIN="$TMP_ROOT/mockbin"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" ]]; then
  case "${3:-}" in
    sgt-witness-demo|sgt-refinery-demo)
      exit 0
      ;;
    *)
      exit 1
      ;;
  esac
fi

exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  SGT_ROOT="$HOME_DIR/sgt" \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/demo"

old_ts="$(date -u -d "@$(( $(date +%s) - 240 ))" +%Y-%m-%dT%H:%M:%S+00:00)"
cat > "$SGT_ROOT/.sgt/refinery-demo-heartbeat.json" <<HB
{
  "timestamp": "$old_ts",
  "cycle": 7,
  "pid": 5252,
  "agent": "refinery",
  "rig": "demo"
}
HB

cat > "$SGT_ROOT/.sgt/witness-demo-heartbeat.json" <<HB
{
  "timestamp": "$old_ts",
  "cycle": 7,
  "pid": 6262,
  "agent": "witness",
  "rig": "demo"
}
HB

cat > "$SGT_ROOT/.sgt/merge-queue/demo-pr123" <<MQ
POLECAT=demo-pr123
RIG=demo
PR=123
QUEUED=$(date -u -d "@$(( $(date +%s) - 600 ))" +%Y-%m-%dT%H:%M:%S+00:00)
MQ

sgt status > "$SGT_ROOT/status.out"
'

STATUS_OUT="$HOME_DIR/sgt/status.out"
if ! grep -q 'refinery/demo' "$STATUS_OUT"; then
  echo "expected refinery/demo in status output" >&2
  exit 1
fi
if ! grep -q 'degraded' "$STATUS_OUT"; then
  echo "expected degraded badge in status output" >&2
  exit 1
fi
if ! grep -q 'queue watchdog: pending=1' "$STATUS_OUT"; then
  echo "expected queue watchdog summary in status output" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
