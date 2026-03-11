#!/usr/bin/env bash
# test_mayor_completion_condition_regression.sh — Mayor must not go idle-green when plan acceptance remains unmet.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin" "$TMP_HOME/mock-bin" "$TMP_HOME/state/issues"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

cat > "$TMP_HOME/mock-bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/tmux"

cat > "$TMP_HOME/mock-bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/openclaw"

cat > "$TMP_HOME/mock-bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/codex"

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${GH_STATE_DIR:?missing GH_STATE_DIR}"
ISSUES_DIR="$STATE_DIR/issues"
mkdir -p "$ISSUES_DIR"

command="${1:-}"
subcommand="${2:-}"
shift 2 || true

case "$command:$subcommand" in
  issue:view)
    issue_number="${1:-}"
    issue_number="${issue_number#\#}"
    issue_file="$ISSUES_DIR/$issue_number.env"
    [[ -f "$issue_file" ]] || exit 1
    state_value="$(sed -n 's/^STATE=//p' "$issue_file" | head -1)"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json|--jq)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    printf '%s\n' "${state_value:-}"
    ;;
  issue:list|pr:list|api:*|label:create|issue:edit|pr:view)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/gh"

COMMON_ENV=(
  "HOME=$TMP_HOME"
  "PATH=$TMP_HOME/mock-bin:$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
  "TERM=${TERM:-xterm}"
  "GH_STATE_DIR=$TMP_HOME/state"
  "SGT_AI_BACKEND=codex"
  "SGT_MAYOR_INTERVAL=1"
  "SGT_MAYOR_DISPATCH_COOLDOWN=0"
)

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo" "$HOME/sgt/.sgt/plan-state"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

now="$(date -Iseconds)"
cat > "$HOME/sgt/.sgt/deacon-heartbeat.json" <<EOF_HEARTBEAT
{"timestamp":"$now"}
EOF_HEARTBEAT
cat > "$HOME/sgt/.sgt/witness-demo-heartbeat.json" <<EOF_HEARTBEAT
{"timestamp":"$now"}
EOF_HEARTBEAT
cat > "$HOME/sgt/.sgt/refinery-demo-heartbeat.json" <<EOF_HEARTBEAT
{"timestamp":"$now"}
EOF_HEARTBEAT

cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "completion_condition": "Run a fresh-state verification on latest main and confirm the operator can complete the workflow.",
  "acceptance": {
    "status": "pending",
    "details": "Fresh-state verification is still required after code merges."
  },
  "tasks": [
    { "id": "verify", "title": "Implement the workflow verification" }
  ]
}
JSON

cat > "$HOME/sgt/.sgt/plan-state/demo.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "tasks": {
    "verify": {
      "status": "dispatched",
      "issue_number": "1",
      "issue_url": "https://github.com/acme/demo/issues/1"
    }
  }
}
JSON

printf 'STATE=%q\n' 'CLOSED' > "$HOME/state/issues/1.env"

sgt _mayor > "$HOME/mayor.out" 2>&1 &
mayor_pid=$!

for _ in $(seq 1 40); do
  if grep -q 'complex issues detected — invoking AI decision' "$HOME/mayor.out" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

kill "$mayor_pid" 2>/dev/null || true
for _ in $(seq 1 20); do
  if ! kill -0 "$mayor_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
kill -9 "$mayor_pid" 2>/dev/null || true
wait "$mayor_pid" 2>/dev/null || true
BASH

OUT_FILE="$TMP_HOME/mayor.out"
STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"
DECISION_LOG="$TMP_HOME/sgt/.sgt/mayor-decisions.log"

grep -q 'plan completion condition unmet on demo after tasks exhausted' "$DECISION_LOG" || {
  echo "expected mayor decision log to record unmet completion condition after tasks exhausted" >&2
  cat "$DECISION_LOG" >&2
  exit 1
}

grep -q 'complex issues detected — invoking AI decision' "$OUT_FILE" || {
  echo "expected unmet completion condition to trigger mayor AI follow-up" >&2
  cat "$OUT_FILE" >&2
  exit 1
}

if grep -q '\[mayor\] all clear' "$OUT_FILE"; then
  echo "mayor incorrectly reported all clear while acceptance was still pending" >&2
  cat "$OUT_FILE" >&2
  exit 1
fi

python3 - "$STATE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
completion = data["completion"]
assert completion["status"] == "pending", completion
assert completion["rollup"] == "tasks-exhausted-awaiting-acceptance", completion
PY

echo "ALL TESTS PASSED"
