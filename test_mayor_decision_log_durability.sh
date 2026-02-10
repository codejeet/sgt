#!/usr/bin/env bash
# test_mayor_decision_log_durability.sh — Regression checks for locked mayor decision logging durability.

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

# Load only the helpers needed for this test.
eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _escape_wake_value)"
eval "$(extract_fn log_event)"
eval "$(extract_fn _decision_log_alert_cooldown_secs)"
eval "$(extract_fn _mayor_decision_log_failure_state_read)"
eval "$(extract_fn _mayor_decision_log_failure_state_write)"
eval "$(extract_fn _mayor_decision_log_failure_state_clear)"
eval "$(extract_fn _mayor_decision_log_append)"
eval "$(extract_fn _mayor_record_decision)"

export SGT_ROOT="$TMP_ROOT/workspace"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_LOG="$SGT_CONFIG/sgt.log"
export SGT_MAYOR_DECISION_LOG_ALERT_STATE="$SGT_CONFIG/mayor-decision-log-alert.state"
export SGT_MAYOR_DECISION_LOG_ALERT_COOLDOWN=120
mkdir -p "$SGT_CONFIG"

LOG_FILE="$SGT_CONFIG/mayor-decisions.log"

# Concurrent append stress: each writer must produce exactly one intact 2-line block
# with no torn/truncated entry lines.
writer_count=120
for i in $(seq 1 "$writer_count"); do
  (
    digit=$((i % 10))
    printf -v pad '%*s' 2048 ''
    pad="${pad// /$digit}"
    entry="entry-$i checksum=$((i * 17)) pad=$pad"
    _mayor_decision_log_append "$entry" "$SGT_ROOT"
  ) &
done
wait

python3 - "$LOG_FILE" "$SGT_ROOT" "$writer_count" <<'PY'
import re
import sys

path, workspace, writer_count_raw = sys.argv[1:4]
writer_count = int(writer_count_raw)
lines = open(path, "r", encoding="utf-8").read().splitlines()

expected_lines = writer_count * 2
if len(lines) != expected_lines:
    raise SystemExit(f"expected {expected_lines} lines ({writer_count} blocks x 2 lines), got {len(lines)}")

header_re = re.compile(r"^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\] workspace=(.+)$")
entry_re = re.compile(r"^entry-(\d+) checksum=(\d+) pad=([0-9]{2048})$")
seen = set()
for idx in range(0, len(lines), 2):
    h, e = lines[idx:idx+2]
    m = header_re.match(h)
    if not m:
        raise SystemExit(f"invalid header format at line {idx+1}: {h!r}")
    if m.group(2) != workspace:
        raise SystemExit(f"unexpected workspace value at line {idx+1}: {m.group(2)!r}")
    em = entry_re.match(e)
    if not em:
        raise SystemExit(f"invalid or truncated entry line at line {idx+2}: {e!r}")
    n = int(em.group(1))
    checksum = int(em.group(2))
    pad = em.group(3)
    if checksum != n * 17:
        raise SystemExit(f"checksum mismatch for entry-{n}: expected {n * 17}, got {checksum}")
    expected_digit = str(n % 10)
    if pad != expected_digit * 2048:
        raise SystemExit(f"interleaved/corrupt pad for entry-{n}")
    if n in seen:
        raise SystemExit(f"duplicate entry id detected: {n}")
    seen.add(n)

expected = set(range(1, writer_count + 1))
if seen != expected:
    raise SystemExit(f"missing/duplicate entries: expected {len(expected)} unique ids, got {len(seen)}")
PY

# Failure path: simulate append+fsync write error (read-only log file), ensure
# explicit warning event is emitted, notify is cooldown deduped, and failure
# state is visible for status rendering.
touch "$LOG_FILE"
chmod 400 "$LOG_FILE"

NOTIFY_LOG="$TMP_ROOT/notify.log"
_mayor_notify_rigger() {
  local msg="${1:-}"
  printf '%s\n' "$msg" >> "$NOTIFY_LOG"
  return 0
}

if _mayor_record_decision "forced failure #1" "durability-test" "$SGT_ROOT"; then
  echo "expected _mayor_record_decision to fail on forced write error" >&2
  exit 1
fi

if ! grep -q 'MAYOR_DECISION_LOG_WRITE_FAILED context=durability-test' "$SGT_LOG"; then
  echo "expected explicit MAYOR_DECISION_LOG_WRITE_FAILED event in log" >&2
  exit 1
fi

if ! grep -q 'notify=sent cooldown=120s' "$SGT_LOG"; then
  echo "expected first failure to send notify with cooldown metadata" >&2
  exit 1
fi

if _mayor_record_decision "forced failure #2" "durability-test" "$SGT_ROOT"; then
  echo "expected _mayor_record_decision to fail on second forced write failure" >&2
  exit 1
fi

if ! grep -q 'notify=suppressed cooldown=120s' "$SGT_LOG"; then
  echo "expected second failure notify to be suppressed by cooldown" >&2
  exit 1
fi

if [[ "$(wc -l < "$NOTIFY_LOG" | tr -d ' ')" != "1" ]]; then
  echo "expected exactly one notify send within cooldown window" >&2
  exit 1
fi

IFS='|' read -r fail_ts fail_context fail_workspace fail_error <<< "$(_mayor_decision_log_failure_state_read)"
if [[ ! "$fail_ts" =~ ^[0-9]+$ ]]; then
  echo "expected failure state timestamp to be recorded for status visibility" >&2
  exit 1
fi
if [[ "$fail_context" != "durability-test" ]]; then
  echo "expected failure state context to match durability-test" >&2
  exit 1
fi

if ! grep -q 'decision-log warning:' "$SGT_SCRIPT"; then
  echo "expected status output path to surface decision-log warning visibility" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
