#!/usr/bin/env bash
# test_mayor_runtime_auto_refresh.sh — Mayor runtime should auto-refresh via handoff before AI invoke when the live prompt exceeds the threshold.

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
exit 0
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
printf 'invoked\n' >> "${CODEX_INVOKE_LOG:?missing CODEX_INVOKE_LOG}"
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
  issue:list)
    exit 0
    ;;
  pr:list|pr:view|api:*|label:create|issue:edit)
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
  "CODEX_INVOKE_LOG=$TMP_HOME/codex-invocations.log"
  "SGT_AI_BACKEND=codex"
  "SGT_MAYOR_INTERVAL=1"
  "SGT_MAYOR_DISPATCH_COOLDOWN=0"
  "SGT_MAYOR_AUTO_REFRESH_TOKENS=150000"
  "SGT_MAYOR_AUTO_REFRESH_COOLDOWN_SECS=900"
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

python3 - <<'PY' "$HOME/sgt/.sgt/mayor-decisions.log"
from pathlib import Path
import sys
line = "runtime-auto-refresh-decision " + ("x" * 40000)
Path(sys.argv[1]).write_text("\n".join([line] * 30) + "\n", encoding="utf-8")
PY

set +e
timeout 10 sgt _mayor > "$HOME/mayor.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "expected mayor runtime to exit cleanly after auto-refresh threshold" >&2
  cat "$HOME/mayor.out" >&2 || true
  exit 1
fi
BASH

OUT_FILE="$TMP_HOME/mayor.out"
LOG_FILE="$TMP_HOME/sgt/sgt.log"
BUDGET_FILE="$TMP_HOME/sgt/.sgt/mayor-prompt-budget.state"
REFRESH_FILE="$TMP_HOME/sgt/.sgt/mayor-auto-refresh.state"
DECISION_LOG="$TMP_HOME/sgt/.sgt/mayor-decisions.log"
CODEX_LOG="$TMP_HOME/codex-invocations.log"

[[ -f "$BUDGET_FILE" ]] || { echo "missing prompt budget state" >&2; exit 1; }
[[ -f "$REFRESH_FILE" ]] || { echo "missing auto-refresh state" >&2; exit 1; }
[[ -f "$DECISION_LOG" ]] || { echo "missing mayor decision log" >&2; exit 1; }

IFS='|' read -r budget_ts budget_measured_at budget_tokens budget_chars budget_threshold budget_over budget_source < "$BUDGET_FILE"
[[ "$budget_tokens" =~ ^[0-9]+$ && "$budget_tokens" -gt "$budget_threshold" ]] || {
  echo "expected over-budget measurement in prompt budget state" >&2
  cat "$BUDGET_FILE" >&2
  exit 1
}
[[ "$budget_over" == "true" ]] || {
  echo "expected prompt budget state to mark over_budget=true" >&2
  cat "$BUDGET_FILE" >&2
  exit 1
}
case "$budget_source" in
  *"/mayor-workspace/CLAUDE.md") ;;
  *)
    echo "expected prompt budget source to be the live mayor prompt file" >&2
    cat "$BUDGET_FILE" >&2
    exit 1
    ;;
esac

IFS='|' read -r refresh_ts refresh_at refresh_trigger refresh_tokens refresh_chars refresh_threshold refresh_handoff refresh_token refresh_status < "$REFRESH_FILE"
[[ "$refresh_trigger" == "ai-cycle-prompt" ]] || {
  echo "expected runtime auto-refresh trigger to record ai-cycle-prompt" >&2
  cat "$REFRESH_FILE" >&2
  exit 1
}
[[ "$refresh_tokens" == "$budget_tokens" ]] || {
  echo "expected refresh state to carry measured token count" >&2
  cat "$REFRESH_FILE" >&2
  exit 1
}
[[ -f "$refresh_handoff" ]] || {
  echo "expected auto-refresh handoff file to exist" >&2
  cat "$REFRESH_FILE" >&2
  exit 1
}
grep -q '^## Auto-Refresh Trigger$' "$refresh_handoff" || {
  echo "expected handoff to record auto-refresh trigger block" >&2
  cat "$refresh_handoff" >&2
  exit 1
}
grep -q 'trigger: ai-cycle-prompt' "$refresh_handoff" || {
  echo "expected handoff to capture runtime trigger name" >&2
  cat "$refresh_handoff" >&2
  exit 1
}

grep -q 'MAYOR_PROMPT_BUDGET scope=shared estimated_tokens=' "$LOG_FILE" || {
  echo "expected prompt budget telemetry in activity log" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -q 'MAYOR_AUTO_REFRESH_TRIGGERED scope=shared trigger=ai-cycle-prompt' "$LOG_FILE" || {
  echo "expected auto-refresh trigger telemetry in activity log" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -q 'MAYOR_AI_CYCLE aborted reason=auto-refresh-threshold' "$LOG_FILE" || {
  echo "expected AI cycle abort telemetry for auto-refresh threshold" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -q 'MAYOR AI CYCLE ABORT reason_code=auto-refresh-threshold' "$DECISION_LOG" || {
  echo "expected decision log to record runtime auto-refresh abort" >&2
  cat "$DECISION_LOG" >&2
  exit 1
}

if [[ -f "$CODEX_LOG" ]] && [[ -s "$CODEX_LOG" ]]; then
  echo "AI backend should not run once runtime auto-refresh fires" >&2
  cat "$CODEX_LOG" >&2
  exit 1
fi

grep -q 'AI cycle aborted — auto-refresh scheduled' "$OUT_FILE" || {
  echo "expected operator-visible stdout for auto-refresh abort" >&2
  cat "$OUT_FILE" >&2
  exit 1
}

echo "ALL TESTS PASSED"
