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
eval "$(extract_fn log_event)"
eval "$(extract_fn _mayor_decision_log_append)"
eval "$(extract_fn _mayor_decision_log_warn_cooldown_secs)"
eval "$(extract_fn _mayor_record_decision)"

export SGT_ROOT="$TMP_ROOT/workspace"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_LOG="$SGT_CONFIG/sgt.log"
export SGT_MAYOR_DECISION_LOG_WARN_STATE="$SGT_CONFIG/mayor-decision-log-warn.state"
export SGT_MAYOR_DECISION_LOG_WARN_COOLDOWN=60
mkdir -p "$SGT_CONFIG"

LOG_FILE="$SGT_CONFIG/mayor-decisions.log"
NOTIFY_LOG="$TMP_ROOT/notify.log"

_mayor_notify_rigger() {
  printf '%s\n' "$1" >> "$NOTIFY_LOG"
}

# Concurrent append stress: each write is a 2-line payload and must remain intact.
for i in $(seq 1 40); do
  (
    entry="entry-$i"
    entry+=$'\n'
    entry+="  payload-$i"
    _mayor_decision_log_append "$entry" "$SGT_ROOT"
  ) &
done
wait

python3 - "$LOG_FILE" "$SGT_ROOT" <<'PY'
import re
import sys

path, workspace = sys.argv[1:3]
lines = open(path, "r", encoding="utf-8").read().splitlines()

if len(lines) != 120:
    raise SystemExit(f"expected 120 lines (40 blocks x 3 lines), got {len(lines)}")

header_re = re.compile(r"^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\] workspace=(.+)$")
seen = set()
for idx in range(0, len(lines), 3):
    h, e, p = lines[idx:idx+3]
    m = header_re.match(h)
    if not m:
        raise SystemExit(f"invalid header format at line {idx+1}: {h!r}")
    if m.group(2) != workspace:
        raise SystemExit(f"unexpected workspace value at line {idx+1}: {m.group(2)!r}")
    if not e.startswith("entry-"):
        raise SystemExit(f"invalid entry line at line {idx+2}: {e!r}")
    n = e.split("-", 1)[1]
    expected_payload = f"  payload-{n}"
    if p != expected_payload:
        raise SystemExit(
            f"interleaved/corrupt payload for entry-{n}: expected {expected_payload!r}, got {p!r}"
        )
    seen.add(int(n))

expected = set(range(1, 41))
if seen != expected:
    raise SystemExit(f"missing/duplicate entries: expected {len(expected)} unique ids, got {len(seen)}")
PY

# Failure path: simulate append error by removing file write permissions.
chmod a-w "$LOG_FILE"

if ! _mayor_record_decision "forced failure 1" "durability-test" "$SGT_ROOT"; then
  echo "expected _mayor_record_decision to remain non-fatal on write failure" >&2
  exit 1
fi

if ! _mayor_record_decision "forced failure 2" "durability-test" "$SGT_ROOT"; then
  echo "expected repeated _mayor_record_decision failure path to remain non-fatal" >&2
  exit 1
fi

if ! grep -q 'MAYOR_DECISION_LOG_WARN context=durability-test' "$SGT_LOG"; then
  echo "expected explicit MAYOR_DECISION_LOG_WARN event in log" >&2
  exit 1
fi

if ! grep -q 'MAYOR_DECISION_LOG_WARN_NOTIFY_SUPPRESS context=durability-test cooldown=60s' "$SGT_LOG"; then
  echo "expected cooldown suppression event for repeated decision-log warning" >&2
  exit 1
fi

notify_count=$(wc -l < "$NOTIFY_LOG" | tr -d ' ')
if [[ "$notify_count" -ne 1 ]]; then
  echo "expected one rigger notification under cooldown, got $notify_count" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
