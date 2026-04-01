#!/usr/bin/env bash
# Regression: duplicate-closed continuation lanes should not be immediately redispatched until the task materially changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin" "$TMP_HOME/mock-bin" "$TMP_HOME/state"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

cat > "$TMP_HOME/mock-bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/openclaw"

cat > "$TMP_HOME/mock-bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
    exit 1
    ;;
  new-session|kill-session)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/tmux"

cat > "$TMP_HOME/mock-bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi
case "${1:-}" in
  fetch)
    exit 0
    ;;
  symbolic-ref)
    echo "refs/remotes/origin/main"
    exit 0
    ;;
  worktree)
    shift
    case "${1:-}" in
      add)
        shift
        if [[ "${1:-}" == "-b" ]]; then
          worktree="$3"
        else
          worktree="$1"
        fi
        mkdir -p "$worktree"
        exit 0
        ;;
      remove)
        exit 0
        ;;
    esac
    ;;
esac
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/git"

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${GH_STATE_DIR:?missing GH_STATE_DIR}"
CREATE_LOG="$STATE_DIR/issue-create.log"
mkdir -p "$STATE_DIR"

case "${1:-}:${2:-}" in
  label:create)
    exit 0
    ;;
  issue:list)
    label=""
    state_filter="open"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --label) label="${2:-}"; shift 2 ;;
        --state) state_filter="${2:-}"; shift 2 ;;
        --json|--limit|--repo) shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$label" == "plan-PKNXT-15" && "$state_filter" == "open" ]]; then
      echo '[]'
    else
      echo '[]'
    fi
    ;;
  issue:view)
    issue_number="${3:-}"
    issue_number="${issue_number#\#}"
    shift 3
    json_fields=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json) json_fields="${2:-}"; shift 2 ;;
        --jq|--repo) shift 2 ;;
        *) shift ;;
      esac
    done
    case "$issue_number:$json_fields" in
      1088:state) echo "CLOSED" ;;
      1092:state) echo "OPEN" ;;
      *) echo "" ;;
    esac
    ;;
  pr:list)
    cat <<'JSON'
[
  {
    "number": 1090,
    "title": "Close duplicate confidence-lift lane request",
    "body": "Closes #1088",
    "mergedAt": "2026-04-01T05:33:42Z"
  }
]
JSON
    ;;
  issue:create)
    title=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title) title="${2:-}"; shift 2 ;;
        --body|--repo|--label) shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s\n' "$title" >> "$CREATE_LOG"
    case "$title" in
      "Explore materially different lane")
        echo "https://github.com/acme/demo/issues/1092"
        exit 0
        ;;
      *)
        echo "unexpected issue creation for title: $title" >&2
        exit 1
        ;;
    esac
    ;;
  issue:edit|pr:view|api:*)
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
  "SGT_MAYOR_DISPATCH_COOLDOWN=0"
)

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo" "$HOME/sgt/.sgt/plan-state"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"
cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "tasks": [
    { "id": "PKNXT-15", "title": "Implement and evaluate late_expiry_taker_h5_only_reset_confirmation_confidence_lift_gate as the immediate next continuation lane" }
  ]
}
JSON
cat > "$HOME/sgt/.sgt/plan-state/demo.json" <<'JSON'
{
  "tasks": {
    "PKNXT-15": {
      "issue_number": "1088",
      "issue_url": "https://github.com/acme/demo/issues/1088",
      "status": "dispatched",
      "updated_at": "2026-04-01T05:28:39Z"
    }
  }
}
JSON

sgt plan tick demo > "$HOME/plan-tick-first.out" 2>&1

cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "tasks": [
    { "id": "PKNXT-15", "title": "Explore materially different lane" }
  ]
}
JSON

sgt plan tick demo > "$HOME/plan-tick-second.out" 2>&1
BASH

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"
CREATE_LOG="$TMP_HOME/state/issue-create.log"
BLOCKER_FILE="$TMP_HOME/sgt/.sgt/plan-blockers/demo--pknxt-15.env"

python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

task = data["tasks"]["PKNXT-15"]

assert task["status"] == "dispatched", task
assert str(task.get("issue_number")) == "1092", task
assert "duplicate_closeout" not in task, task
PY

grep -q 'PLAN_TASK_DUPLICATE_CLOSEOUT rig=demo task=PKNXT-15 issue=#1088 pr=#1090' "$TMP_HOME/sgt/sgt.log" || {
  echo "expected duplicate closeout telemetry" >&2
  exit 1
}

grep -q 'reason_code=duplicate-closeout-awaiting-successor' "$TMP_HOME/sgt/sgt.log" || {
  echo "expected duplicate closeout movement blocker" >&2
  exit 1
}

grep -qx 'Explore materially different lane' "$CREATE_LOG" || {
  echo "expected only the materially different successor to be dispatched" >&2
  cat "$CREATE_LOG" >&2
  exit 1
}

if [[ -f "$BLOCKER_FILE" ]] && grep -q '^STATUS=open$' "$BLOCKER_FILE"; then
  echo "expected duplicate closeout blocker to resolve after successor changed" >&2
  cat "$BLOCKER_FILE" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
